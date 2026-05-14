-- ============================================
-- PadelApp — Initial Database Schema
-- Migration: 001_initial_schema
-- ============================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- Full-text search

-- ============================================
-- PROFILES (extends Supabase auth.users)
-- ============================================
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username VARCHAR(30) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    -- Padel data
    skill_level VARCHAR(20) DEFAULT 'beginner' CHECK (skill_level IN ('beginner', 'intermediate', 'advanced', 'pro')),
    preferred_position VARCHAR(10) DEFAULT 'any' CHECK (preferred_position IN ('drive', 'reves', 'any')),
    dominant_hand VARCHAR(10) DEFAULT 'right' CHECK (dominant_hand IN ('right', 'left')),
    -- ELO Rating
    elo_rating INTEGER DEFAULT 1200 NOT NULL,
    elo_matches_played INTEGER DEFAULT 0 NOT NULL,
    elo_confidence DECIMAL(3,2) DEFAULT 0.00,
    elo_highest INTEGER DEFAULT 1200,
    -- Geolocation
    location GEOGRAPHY(POINT, 4326),
    city VARCHAR(100),
    country VARCHAR(50),
    -- Meta
    locale VARCHAR(5) DEFAULT 'es' CHECK (locale IN ('es', 'en')),
    is_verified BOOLEAN DEFAULT FALSE,
    is_premium BOOLEAN DEFAULT FALSE,
    is_online BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    push_subscription JSONB,
    notification_preferences JSONB DEFAULT '{
        "matches": true,
        "chat": true,
        "challenges": true,
        "feed": true,
        "sounds": true
    }'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_profiles_elo ON public.profiles(elo_rating DESC);
CREATE INDEX idx_profiles_location ON public.profiles USING GIST(location);
CREATE INDEX idx_profiles_city ON public.profiles(city);
CREATE INDEX idx_profiles_skill ON public.profiles(skill_level);

-- ============================================
-- FOLLOWS
-- ============================================
CREATE TABLE public.follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(follower_id, following_id),
    CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_follower ON public.follows(follower_id);
CREATE INDEX idx_follows_following ON public.follows(following_id);

-- ============================================
-- COURTS (canchas suscritas al servicio)
-- ============================================
CREATE TABLE public.courts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES public.profiles(id),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(200) UNIQUE NOT NULL,
    description TEXT,
    address TEXT NOT NULL,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    city VARCHAR(100),
    country VARCHAR(50),
    phone VARCHAR(20),
    email VARCHAR(200),
    website TEXT,
    cover_image_url TEXT,
    logo_url TEXT,
    -- Features
    total_courts SMALLINT DEFAULT 1 CHECK (total_courts > 0),
    surface_type VARCHAR(30) DEFAULT 'artificial_grass' CHECK (surface_type IN ('artificial_grass', 'concrete', 'carpet', 'synthetic')),
    is_indoor BOOLEAN DEFAULT FALSE,
    has_lighting BOOLEAN DEFAULT TRUE,
    has_parking BOOLEAN DEFAULT FALSE,
    -- Services
    has_restaurant BOOLEAN DEFAULT FALSE,
    has_bar BOOLEAN DEFAULT FALSE,
    has_locker_rooms BOOLEAN DEFAULT TRUE,
    has_shop BOOLEAN DEFAULT FALSE,
    -- Business
    subscription_tier VARCHAR(20) DEFAULT 'basic' CHECK (subscription_tier IN ('basic', 'pro', 'enterprise')),
    is_active BOOLEAN DEFAULT TRUE,
    -- Schedule
    operating_hours JSONB DEFAULT '{
        "mon": {"open": "08:00", "close": "22:00"},
        "tue": {"open": "08:00", "close": "22:00"},
        "wed": {"open": "08:00", "close": "22:00"},
        "thu": {"open": "08:00", "close": "22:00"},
        "fri": {"open": "08:00", "close": "22:00"},
        "sat": {"open": "09:00", "close": "23:00"},
        "sun": {"open": "09:00", "close": "21:00"}
    }'::jsonb,
    price_per_hour DECIMAL(8,2),
    currency VARCHAR(3) DEFAULT 'USD',
    -- Stats
    avg_rating DECIMAL(2,1) DEFAULT 0.0,
    total_reviews INTEGER DEFAULT 0,
    total_bookings INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_courts_location ON public.courts USING GIST(location);
CREATE INDEX idx_courts_city ON public.courts(city);
CREATE INDEX idx_courts_active ON public.courts(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_courts_slug ON public.courts(slug);

-- ============================================
-- COURT MENU (servicios de comida/bebida)
-- ============================================
CREATE TABLE public.court_menu_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES public.courts(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    name_en VARCHAR(100),
    display_order SMALLINT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE TABLE public.court_menu_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES public.courts(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.court_menu_categories(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    name_en VARCHAR(150),
    description TEXT,
    description_en TEXT,
    price DECIMAL(8,2) NOT NULL,
    image_url TEXT,
    is_available BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    allergens TEXT[],
    display_order SMALLINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_menu_items_court ON public.court_menu_items(court_id);
CREATE INDEX idx_menu_items_category ON public.court_menu_items(category_id);

-- ============================================
-- COURT REVIEWS
-- ============================================
CREATE TABLE public.court_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES public.courts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(court_id, user_id)
);

-- ============================================
-- BOOKINGS (reservas)
-- ============================================
CREATE TABLE public.bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES public.courts(id),
    booked_by UUID NOT NULL REFERENCES public.profiles(id),
    court_number SMALLINT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed')),
    total_price DECIMAL(8,2),
    -- Extra services ordered
    menu_orders JSONB DEFAULT '[]'::jsonb,
    table_reservation BOOLEAN DEFAULT FALSE,
    table_size SMALLINT,
    notes TEXT,
    cancellation_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CHECK (end_time > start_time)
);

CREATE INDEX idx_bookings_court ON public.bookings(court_id);
CREATE INDEX idx_bookings_user ON public.bookings(booked_by);
CREATE INDEX idx_bookings_time ON public.bookings(start_time, end_time);
CREATE INDEX idx_bookings_status ON public.bookings(status) WHERE status IN ('pending', 'confirmed');

-- ============================================
-- MATCHES (partidos)
-- ============================================
CREATE TABLE public.matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID REFERENCES public.courts(id),
    booking_id UUID REFERENCES public.bookings(id),
    -- Match type
    match_type VARCHAR(20) NOT NULL CHECK (match_type IN ('manual', 'random', 'challenge')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled')),
    -- Config
    scheduled_at TIMESTAMPTZ NOT NULL,
    duration_minutes SMALLINT DEFAULT 90 CHECK (duration_minutes > 0),
    is_competitive BOOLEAN DEFAULT TRUE,
    -- Payment
    payment_method VARCHAR(20) CHECK (payment_method IN ('split', 'host_pays', 'winner_pays', 'free')),
    total_cost DECIMAL(8,2),
    -- Result
    score_team_a VARCHAR(30),
    score_team_b VARCHAR(30),
    winner_team VARCHAR(1) CHECK (winner_team IN ('a', 'b')),
    -- ELO changes
    elo_change_team_a INTEGER DEFAULT 0,
    elo_change_team_b INTEGER DEFAULT 0,
    -- Meta
    created_by UUID NOT NULL REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_matches_court ON public.matches(court_id);
CREATE INDEX idx_matches_status ON public.matches(status);
CREATE INDEX idx_matches_date ON public.matches(scheduled_at DESC);
CREATE INDEX idx_matches_creator ON public.matches(created_by);

-- ============================================
-- MATCH PLAYERS
-- ============================================
CREATE TABLE public.match_players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES public.profiles(id),
    team VARCHAR(1) NOT NULL CHECK (team IN ('a', 'b')),
    position VARCHAR(10) CHECK (position IN ('drive', 'reves')),
    status VARCHAR(20) DEFAULT 'invited' CHECK (status IN ('invited', 'accepted', 'declined')),
    elo_before INTEGER,
    elo_after INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(match_id, player_id)
);

CREATE INDEX idx_match_players_match ON public.match_players(match_id);
CREATE INDEX idx_match_players_player ON public.match_players(player_id);

-- ============================================
-- MATCHMAKING QUEUE
-- ============================================
CREATE TABLE public.matchmaking_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'waiting' CHECK (status IN ('waiting', 'matched', 'expired', 'cancelled')),
    preferred_time_start TIMESTAMPTZ,
    preferred_time_end TIMESTAMPTZ,
    preferred_duration SMALLINT DEFAULT 90,
    max_distance_km INTEGER DEFAULT 25,
    elo_range_min INTEGER,
    elo_range_max INTEGER,
    location GEOGRAPHY(POINT, 4326),
    matched_with UUID REFERENCES public.profiles(id),
    match_id UUID REFERENCES public.matches(id),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 minutes')
);

CREATE INDEX idx_queue_status ON public.matchmaking_queue(status) WHERE status = 'waiting';
CREATE INDEX idx_queue_player ON public.matchmaking_queue(player_id);

-- ============================================
-- CHALLENGES (retos)
-- ============================================
CREATE TABLE public.challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenger_id UUID NOT NULL REFERENCES public.profiles(id),
    challenged_id UUID NOT NULL REFERENCES public.profiles(id),
    match_id UUID REFERENCES public.matches(id),
    message TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
    elo_diff INTEGER NOT NULL,
    preferred_date TIMESTAMPTZ,
    preferred_court_id UUID REFERENCES public.courts(id),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '48 hours'),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CHECK (challenger_id != challenged_id)
);

CREATE INDEX idx_challenges_challenger ON public.challenges(challenger_id);
CREATE INDEX idx_challenges_challenged ON public.challenges(challenged_id);
CREATE INDEX idx_challenges_status ON public.challenges(status) WHERE status = 'pending';

-- ============================================
-- POSTS (microblogging)
-- ============================================
CREATE TABLE public.posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL CHECK (char_length(content) <= 500),
    media_urls TEXT[] DEFAULT '{}',
    media_types TEXT[] DEFAULT '{}',
    -- Engagement counters (denormalized for performance)
    likes_count INTEGER DEFAULT 0 NOT NULL,
    comments_count INTEGER DEFAULT 0 NOT NULL,
    reposts_count INTEGER DEFAULT 0 NOT NULL,
    -- Visibility
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'private')),
    -- Reference to match
    match_id UUID REFERENCES public.matches(id),
    -- Meta
    is_pinned BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_posts_author ON public.posts(author_id);
CREATE INDEX idx_posts_created ON public.posts(created_at DESC);
CREATE INDEX idx_posts_content_search ON public.posts USING GIN(to_tsvector('spanish', content));

-- ============================================
-- COMMENTS
-- ============================================
CREATE TABLE public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL CHECK (char_length(content) <= 300),
    likes_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_comments_post ON public.comments(post_id);
CREATE INDEX idx_comments_parent ON public.comments(parent_id);

-- ============================================
-- LIKES
-- ============================================
CREATE TABLE public.likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, post_id),
    CHECK (
        (post_id IS NOT NULL AND comment_id IS NULL) OR
        (post_id IS NULL AND comment_id IS NOT NULL)
    )
);

CREATE INDEX idx_likes_post ON public.likes(post_id) WHERE post_id IS NOT NULL;
CREATE INDEX idx_likes_user ON public.likes(user_id);

-- ============================================
-- CONVERSATIONS (chat DM)
-- ============================================
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(20) DEFAULT 'direct' CHECK (type IN ('direct', 'group', 'match')),
    name VARCHAR(100),
    avatar_url TEXT,
    match_id UUID REFERENCES public.matches(id),
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE TABLE public.conversation_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    is_muted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(conversation_id, user_id)
);

CREATE INDEX idx_conv_participants_user ON public.conversation_participants(user_id);
CREATE INDEX idx_conv_participants_conv ON public.conversation_participants(conversation_id);

-- ============================================
-- MESSAGES
-- ============================================
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id),
    content TEXT,
    media_url TEXT,
    media_type VARCHAR(20) DEFAULT 'text' CHECK (media_type IN ('text', 'image', 'video', 'audio', 'location', 'match_invite')),
    reply_to_id UUID REFERENCES public.messages(id),
    is_edited BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_messages_conversation ON public.messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON public.messages(sender_id);

-- ============================================
-- NOTIFICATIONS
-- ============================================
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type VARCHAR(30) NOT NULL CHECK (type IN (
        'match_invite', 'match_confirmed', 'match_result',
        'challenge_received', 'challenge_accepted', 'challenge_declined',
        'new_message', 'new_follower',
        'post_like', 'post_comment', 'post_repost',
        'booking_confirmed', 'booking_cancelled',
        'matchmaking_found', 'system'
    )),
    title VARCHAR(200) NOT NULL,
    body TEXT,
    data JSONB DEFAULT '{}'::jsonb,
    is_read BOOLEAN DEFAULT FALSE,
    is_push_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_notifications_user ON public.notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON public.notifications(user_id) WHERE is_read = FALSE;

-- ============================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.courts
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.bookings
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.matches
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.conversations
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.court_menu_items
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, username, display_name, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || substr(NEW.id::text, 1, 8)),
        COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'full_name', 'Padeler'),
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- UPDATE POST COUNTERS (likes_count, comments_count)
-- ============================================
CREATE OR REPLACE FUNCTION public.update_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.post_id IS NOT NULL THEN
        UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' AND OLD.post_id IS NOT NULL THEN
        UPDATE public.posts SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_like_change
    AFTER INSERT OR DELETE ON public.likes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_likes_count();

CREATE OR REPLACE FUNCTION public.update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts SET comments_count = comments_count - 1 WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_comment_change
    AFTER INSERT OR DELETE ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.update_post_comments_count();

-- ============================================
-- UPDATE CONVERSATION last_message_at
-- ============================================
CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations SET last_message_at = NOW() WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_message
    AFTER INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.update_conversation_last_message();
