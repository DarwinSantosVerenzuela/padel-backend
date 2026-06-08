-- ============================================
-- Tak Tak — Activity Analytics + Recommendations
-- Migration: 005_activity_analytics
-- ============================================

-- ============================================
-- USER ACTIVITY LOG — tracks all user interactions
-- ============================================
CREATE TABLE IF NOT EXISTS public.user_activity_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    action VARCHAR(30) NOT NULL CHECK (action IN (
        'post_create', 'post_like', 'post_dislike', 'post_repost',
        'comment_create', 'comment_like',
        'follow', 'unfollow',
        'match_play', 'match_win', 'match_lose',
        'challenge_send', 'challenge_accept',
        'court_visit', 'court_review', 'court_bookmark',
        'profile_view', 'search_player',
        'chat_message', 'share_post'
    )),
    target_type VARCHAR(20) CHECK (target_type IN (
        'post', 'comment', 'user', 'match', 'court', 'challenge'
    )),
    target_id UUID,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_activity_user ON public.user_activity_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_action ON public.user_activity_log(action);
CREATE INDEX IF NOT EXISTS idx_activity_target ON public.user_activity_log(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_activity_recent ON public.user_activity_log(created_at DESC);

-- ============================================
-- USER INTEREST PROFILE — calculated engagement data
-- ============================================
CREATE TABLE IF NOT EXISTS public.user_interest_profile (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    posts_count INTEGER DEFAULT 0,
    likes_given INTEGER DEFAULT 0,
    likes_received INTEGER DEFAULT 0,
    comments_given INTEGER DEFAULT 0,
    reposts_given INTEGER DEFAULT 0,
    matches_played INTEGER DEFAULT 0,
    matches_won INTEGER DEFAULT 0,
    avg_session_minutes DECIMAL(6,2) DEFAULT 0,
    preferred_days JSONB DEFAULT '[]',
    preferred_hours JSONB DEFAULT '[]',
    favorite_court_ids UUID[] DEFAULT '{}',
    top_interacted_users UUID[] DEFAULT '{}',
    engagement_score INTEGER DEFAULT 0,
    calculated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TRANSLATIONS CACHE — for inline translation
-- ============================================
CREATE TABLE IF NOT EXISTS public.translations_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type VARCHAR(10) NOT NULL CHECK (source_type IN ('post', 'comment', 'message')),
    source_id UUID NOT NULL,
    source_lang VARCHAR(5) NOT NULL,
    target_lang VARCHAR(5) NOT NULL,
    translated_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(source_id, target_lang)
);

CREATE INDEX IF NOT EXISTS idx_translations_lookup ON public.translations_cache(source_id, target_lang);

-- ============================================
-- AUTO-LOG TRIGGERS
-- ============================================

-- Auto-log post creation
CREATE OR REPLACE FUNCTION public.log_post_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
    VALUES (NEW.author_id, 'post_create', 'post', NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_post_log ON public.posts;
CREATE TRIGGER on_post_log AFTER INSERT ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.log_post_activity();

-- Auto-log likes
CREATE OR REPLACE FUNCTION public.log_like_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.post_id IS NOT NULL THEN
        INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
        VALUES (NEW.user_id, 'post_like', 'post', NEW.post_id);
    ELSIF NEW.comment_id IS NOT NULL THEN
        INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
        VALUES (NEW.user_id, 'comment_like', 'comment', NEW.comment_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_like_log ON public.likes;
CREATE TRIGGER on_like_log AFTER INSERT ON public.likes
    FOR EACH ROW EXECUTE FUNCTION public.log_like_activity();

-- Auto-log comments
CREATE OR REPLACE FUNCTION public.log_comment_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
    VALUES (NEW.author_id, 'comment_create', 'comment', NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_comment_log ON public.comments;
CREATE TRIGGER on_comment_log AFTER INSERT ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.log_comment_activity();

-- Auto-log follows
CREATE OR REPLACE FUNCTION public.log_follow_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
        VALUES (NEW.follower_id, 'follow', 'user', NEW.following_id);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO public.user_activity_log (user_id, action, target_type, target_id)
        VALUES (OLD.follower_id, 'unfollow', 'user', OLD.following_id);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_follow_log ON public.follows;
CREATE TRIGGER on_follow_log AFTER INSERT OR DELETE ON public.follows
    FOR EACH ROW EXECUTE FUNCTION public.log_follow_activity();

-- Auto-log chat messages
CREATE OR REPLACE FUNCTION public.log_message_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_activity_log (user_id, action, target_type, target_id, metadata)
    VALUES (NEW.sender_id, 'chat_message', 'user', NULL,
        jsonb_build_object('conversation_id', NEW.conversation_id));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_message_log ON public.messages;
CREATE TRIGGER on_message_log AFTER INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.log_message_activity();

-- ============================================
-- RECOMMEND PLAY PARTNERS (smart function)
-- ============================================
CREATE OR REPLACE FUNCTION public.recommend_play_partners(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    user_id UUID,
    display_name VARCHAR,
    username VARCHAR,
    avatar_url TEXT,
    avatar_emoji TEXT,
    elo_rating INTEGER,
    skill_level VARCHAR,
    city VARCHAR,
    distance_km DOUBLE PRECISION,
    compatibility_score INTEGER,
    reason TEXT
) AS $$
DECLARE
    v_elo INTEGER;
    v_skill VARCHAR;
    v_location GEOGRAPHY;
    v_position VARCHAR;
BEGIN
    SELECT p.elo_rating, p.skill_level, p.location, p.preferred_position
    INTO v_elo, v_skill, v_location, v_position
    FROM public.profiles p WHERE p.id = p_user_id;

    RETURN QUERY
    SELECT
        p.id AS user_id,
        p.display_name,
        p.username,
        p.avatar_url,
        p.avatar_emoji,
        p.elo_rating,
        p.skill_level,
        p.city,
        CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
             THEN ROUND((ST_Distance(p.location, v_location) / 1000)::numeric, 1)::double precision
             ELSE 999.0
        END AS distance_km,
        (
            GREATEST(0, 35 - ABS(p.elo_rating - v_elo) / 10) +
            CASE WHEN p.skill_level = v_skill THEN 20 ELSE 0 END +
            CASE WHEN v_position = 'drive' AND p.preferred_position = 'reves' THEN 15
                 WHEN v_position = 'reves' AND p.preferred_position = 'drive' THEN 15
                 WHEN v_position = 'any' OR p.preferred_position = 'any' THEN 10
                 ELSE 5 END +
            CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
                 THEN GREATEST(0, 20 - (ST_Distance(p.location, v_location) / 5000)::integer)
                 ELSE 0 END +
            LEAST(10, (SELECT COUNT(*)::integer FROM public.user_activity_log
                       WHERE user_activity_log.user_id = p.id AND created_at > NOW() - INTERVAL '7 days'))
        )::integer AS compatibility_score,
        CASE
            WHEN ABS(p.elo_rating - v_elo) < 100 THEN 'Nivel similar al tuyo'
            WHEN v_position = 'drive' AND p.preferred_position = 'reves' THEN 'Complemento perfecto (revés)'
            WHEN v_position = 'reves' AND p.preferred_position = 'drive' THEN 'Complemento perfecto (drive)'
            ELSE 'Jugador activo en tu zona'
        END AS reason
    FROM public.profiles p
    WHERE p.id != p_user_id
      AND (p.is_online = TRUE OR p.last_seen_at > NOW() - INTERVAL '7 days')
    ORDER BY compatibility_score DESC, distance_km ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- GET USER ANALYTICS (dashboard RPC)
-- ============================================
CREATE OR REPLACE FUNCTION public.get_user_analytics(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_posts', (SELECT COUNT(*) FROM posts WHERE author_id = p_user_id),
        'total_likes_given', (SELECT COUNT(*) FROM likes WHERE user_id = p_user_id),
        'total_likes_received', (SELECT COALESCE(SUM(likes_count), 0) FROM posts WHERE author_id = p_user_id),
        'total_comments', (SELECT COUNT(*) FROM comments WHERE author_id = p_user_id),
        'matches_played', (SELECT COUNT(*) FROM match_players WHERE player_id = p_user_id),
        'matches_won', (SELECT COUNT(*) FROM match_players mp
                        JOIN matches m ON m.id = mp.match_id
                        WHERE mp.player_id = p_user_id AND m.winner_team = mp.team),
        'followers_count', (SELECT COUNT(*) FROM follows WHERE following_id = p_user_id),
        'following_count', (SELECT COUNT(*) FROM follows WHERE follower_id = p_user_id)
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- RLS POLICIES for new tables
-- ============================================

ALTER TABLE public.user_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_interest_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.translations_cache ENABLE ROW LEVEL SECURITY;

-- Activity log: users can read their own
CREATE POLICY "Users can view own activity" ON public.user_activity_log
    FOR SELECT USING (auth.uid() = user_id);

-- Activity log: insert via triggers (SECURITY DEFINER)
CREATE POLICY "System can insert activity" ON public.user_activity_log
    FOR INSERT WITH CHECK (true);

-- Interest profile: users can read their own
CREATE POLICY "Users can view own interest profile" ON public.user_interest_profile
    FOR SELECT USING (auth.uid() = user_id);

-- Translations cache: everyone can read
CREATE POLICY "Anyone can read translations" ON public.translations_cache
    FOR SELECT USING (true);

-- Translations cache: authenticated users can insert
CREATE POLICY "Authenticated can insert translations" ON public.translations_cache
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');
