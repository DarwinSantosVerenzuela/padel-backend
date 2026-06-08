-- ============================================
-- PadelApp — Analytics Enhancements
-- Migration: 007_analytics_enhancements
-- Extends 005_activity_analytics with new actions,
-- enriched triggers, and dashboard views
-- ============================================

-- ============================================
-- 1. Expand action CHECK constraint
-- ============================================
ALTER TABLE public.user_activity_log 
DROP CONSTRAINT IF EXISTS user_activity_log_action_check;

ALTER TABLE public.user_activity_log 
ADD CONSTRAINT user_activity_log_action_check CHECK (action IN (
    -- Posts
    'post_create', 'post_like', 'post_dislike', 'post_repost',
    -- Comments
    'comment_create', 'comment_like',
    -- Social
    'follow', 'unfollow',
    -- Matches
    'match_play', 'match_win', 'match_lose',
    -- Challenges
    'challenge_send', 'challenge_accept',
    -- Courts
    'court_visit', 'court_review', 'court_bookmark',
    -- Discovery
    'profile_view', 'search_player',
    -- Messaging
    'chat_message',
    -- Sharing
    'share_post',
    -- New: Media & Location
    'photo_upload', 'location_share',
    -- New: Reactions
    'emoji_react',
    -- New: Auth
    'password_reset'
));

-- ============================================
-- 2. Enrich post activity trigger with metadata
-- ============================================
CREATE OR REPLACE FUNCTION public.log_post_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_activity_log (user_id, action, target_type, target_id, metadata)
    VALUES (NEW.author_id, 'post_create', 'post', NEW.id,
        jsonb_build_object(
            'has_media', COALESCE(array_length(NEW.media_urls, 1), 0) > 0,
            'media_count', COALESCE(array_length(NEW.media_urls, 1), 0),
            'media_types', COALESCE(NEW.media_types, ARRAY[]::text[]),
            'has_location', NEW.location IS NOT NULL,
            'location', COALESCE(NEW.location, ''),
            'visibility', COALESCE(NEW.visibility, 'public'),
            'content_length', LENGTH(NEW.content)
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS on_post_log ON public.posts;
CREATE TRIGGER on_post_log AFTER INSERT ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.log_post_activity();

-- ============================================
-- 3. Add new columns to user_interest_profile
-- ============================================
ALTER TABLE public.user_interest_profile 
    ADD COLUMN IF NOT EXISTS photos_uploaded INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS locations_shared INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS dislikes_given INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS shares_given INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS comment_likes_given INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS most_used_location VARCHAR(200),
    ADD COLUMN IF NOT EXISTS avg_content_length INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS media_post_ratio DECIMAL(4,3) DEFAULT 0;

-- ============================================
-- 4. Update get_user_analytics RPC
-- ============================================
CREATE OR REPLACE FUNCTION public.get_user_analytics(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    v_total_posts INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total_posts FROM posts WHERE author_id = p_user_id;

    SELECT jsonb_build_object(
        -- Core metrics
        'total_posts', v_total_posts,
        'total_likes_given', (SELECT COUNT(*) FROM likes WHERE user_id = p_user_id AND post_id IS NOT NULL),
        'total_likes_received', (SELECT COALESCE(SUM(likes_count), 0) FROM posts WHERE author_id = p_user_id),
        'total_comments', (SELECT COUNT(*) FROM comments WHERE author_id = p_user_id),
        'matches_played', (SELECT COUNT(*) FROM match_players WHERE player_id = p_user_id),
        'matches_won', (SELECT COUNT(*) FROM match_players mp
                        JOIN matches m ON m.id = mp.match_id
                        WHERE mp.player_id = p_user_id AND m.winner_team = mp.team),
        'followers_count', (SELECT COUNT(*) FROM follows WHERE following_id = p_user_id),
        'following_count', (SELECT COUNT(*) FROM follows WHERE follower_id = p_user_id),
        
        -- New media metrics
        'photos_uploaded', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'photo_upload'),
        'locations_shared', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'location_share'),
        'posts_with_media', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'post_create' 
            AND (metadata->>'has_media')::boolean = true),
        'posts_with_location', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'post_create' 
            AND (metadata->>'has_location')::boolean = true),
            
        -- Engagement metrics  
        'comment_likes_given', (SELECT COUNT(*) FROM likes 
            WHERE user_id = p_user_id AND comment_id IS NOT NULL),
        'dislikes_given', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'post_dislike'),
        'reposts_given', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'post_repost'),
        'shares_given', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'share_post'),
        'court_visits', (SELECT COUNT(*) FROM user_activity_log 
            WHERE user_id = p_user_id AND action = 'court_visit'),
            
        -- Engagement rate
        'engagement_rate', CASE WHEN v_total_posts > 0 
            THEN ROUND(
                ((SELECT COUNT(*) FROM likes l JOIN posts p ON l.post_id = p.id WHERE p.author_id = p_user_id) +
                 (SELECT COUNT(*) FROM comments c JOIN posts p ON c.post_id = p.id WHERE p.author_id = p_user_id))::numeric 
                / v_total_posts, 2) 
            ELSE 0 END,
            
        -- Activity timeline (last 7 days)
        'daily_actions_7d', (
            SELECT jsonb_agg(jsonb_build_object(
                'date', d.day::text,
                'count', COALESCE(a.cnt, 0)
            ))
            FROM generate_series(
                CURRENT_DATE - INTERVAL '6 days', 
                CURRENT_DATE, 
                '1 day'
            ) AS d(day)
            LEFT JOIN (
                SELECT date_trunc('day', created_at)::date AS day, COUNT(*) AS cnt
                FROM user_activity_log WHERE user_id = p_user_id
                AND created_at > CURRENT_DATE - INTERVAL '7 days'
                GROUP BY date_trunc('day', created_at)::date
            ) a ON a.day = d.day
        )
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- 5. Daily activity summary view (for admin dashboard)
-- ============================================
CREATE OR REPLACE VIEW public.daily_activity_summary AS
SELECT 
    date_trunc('day', created_at)::date AS activity_date,
    action,
    COUNT(*) AS action_count,
    COUNT(DISTINCT user_id) AS unique_users
FROM public.user_activity_log
GROUP BY date_trunc('day', created_at)::date, action
ORDER BY activity_date DESC, action_count DESC;

-- ============================================
-- 6. User engagement leaderboard view
-- ============================================
CREATE OR REPLACE VIEW public.user_engagement_leaderboard AS
SELECT 
    p.id AS user_id,
    p.display_name,
    p.username,
    p.avatar_emoji,
    COUNT(DISTINCT CASE WHEN a.action = 'post_create' THEN a.id END) AS posts,
    COUNT(DISTINCT CASE WHEN a.action IN ('post_like', 'comment_like') THEN a.id END) AS likes,
    COUNT(DISTINCT CASE WHEN a.action = 'comment_create' THEN a.id END) AS comments,
    COUNT(DISTINCT CASE WHEN a.action = 'photo_upload' THEN a.id END) AS photos,
    COUNT(DISTINCT CASE WHEN a.action = 'location_share' THEN a.id END) AS locations,
    COUNT(a.id) AS total_actions,
    MAX(a.created_at) AS last_active
FROM public.profiles p
LEFT JOIN public.user_activity_log a ON a.user_id = p.id
    AND a.created_at > NOW() - INTERVAL '30 days'
GROUP BY p.id, p.display_name, p.username, p.avatar_emoji
ORDER BY total_actions DESC;

-- ============================================
-- 7. RLS for new views (views inherit table RLS)
-- ============================================
-- daily_activity_summary: admin only (no public RLS needed, will use admin client)
-- user_engagement_leaderboard: public read
