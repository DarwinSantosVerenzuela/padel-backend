-- ============================================
-- PadelApp — PostGIS Functions + Utility RPCs
-- Migration: 003_functions
-- ============================================

-- Find nearby courts using PostGIS
CREATE OR REPLACE FUNCTION public.find_nearby_courts(
    user_lat DOUBLE PRECISION,
    user_lng DOUBLE PRECISION,
    radius_km INTEGER DEFAULT 25,
    max_results INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID, name VARCHAR, slug VARCHAR, address TEXT, city VARCHAR, country VARCHAR,
    cover_image_url TEXT, logo_url TEXT, total_courts SMALLINT, surface_type VARCHAR,
    is_indoor BOOLEAN, has_lighting BOOLEAN, has_restaurant BOOLEAN, has_bar BOOLEAN,
    price_per_hour DECIMAL, currency VARCHAR, avg_rating DECIMAL, total_reviews INTEGER,
    distance_km DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id, c.name, c.slug, c.address, c.city, c.country,
        c.cover_image_url, c.logo_url, c.total_courts, c.surface_type,
        c.is_indoor, c.has_lighting, c.has_restaurant, c.has_bar,
        c.price_per_hour, c.currency, c.avg_rating, c.total_reviews,
        ROUND((ST_Distance(
            c.location::geography,
            ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography
        ) / 1000)::numeric, 2)::double precision AS distance_km
    FROM public.courts c
    WHERE c.is_active = TRUE
    AND ST_DWithin(
        c.location::geography,
        ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography,
        radius_km * 1000
    )
    ORDER BY distance_km ASC
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql STABLE;

-- Update user location
CREATE OR REPLACE FUNCTION public.update_user_location(
    p_user_id UUID,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.profiles
    SET location = ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
        updated_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment ELO matches played
CREATE OR REPLACE FUNCTION public.increment_elo_matches(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE public.profiles
    SET elo_matches_played = elo_matches_played + 1
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Find existing DM conversation between two users
CREATE OR REPLACE FUNCTION public.find_existing_dm(user_a UUID, user_b UUID)
RETURNS SETOF public.conversations AS $$
BEGIN
    RETURN QUERY
    SELECT c.*
    FROM public.conversations c
    WHERE c.type = 'direct'
    AND c.id IN (
        SELECT cp1.conversation_id
        FROM public.conversation_participants cp1
        JOIN public.conversation_participants cp2 ON cp1.conversation_id = cp2.conversation_id
        WHERE cp1.user_id = user_a AND cp2.user_id = user_b
    )
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- Update court average rating
CREATE OR REPLACE FUNCTION public.update_court_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.courts SET
        avg_rating = (SELECT ROUND(AVG(rating)::numeric, 1) FROM public.court_reviews WHERE court_id = COALESCE(NEW.court_id, OLD.court_id)),
        total_reviews = (SELECT COUNT(*) FROM public.court_reviews WHERE court_id = COALESCE(NEW.court_id, OLD.court_id))
    WHERE id = COALESCE(NEW.court_id, OLD.court_id);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_review_change
    AFTER INSERT OR UPDATE OR DELETE ON public.court_reviews
    FOR EACH ROW EXECUTE FUNCTION public.update_court_rating();
