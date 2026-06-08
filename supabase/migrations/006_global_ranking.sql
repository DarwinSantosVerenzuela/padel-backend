-- ============================================
-- Migration: 006_global_ranking
-- Adds global ranking position tracking
-- ============================================

-- Add columns for ranking tracking
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS current_ranking INTEGER,
  ADD COLUMN IF NOT EXISTS best_ranking INTEGER,
  ADD COLUMN IF NOT EXISTS win_streak INTEGER DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS best_win_streak INTEGER DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_wins INTEGER DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_losses INTEGER DEFAULT 0 NOT NULL;

-- Index for fast ranking queries
CREATE INDEX IF NOT EXISTS idx_profiles_ranking ON public.profiles(current_ranking ASC NULLS LAST);

-- ============================================
-- Function: Recalculate global rankings
-- Assigns ranking positions based on ELO rating
-- Only considers users with at least 1 match played
-- ============================================
CREATE OR REPLACE FUNCTION public.recalculate_global_rankings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r RECORD;
  pos INTEGER := 0;
BEGIN
  -- Reset all rankings first
  UPDATE public.profiles SET current_ranking = NULL WHERE current_ranking IS NOT NULL;

  -- Assign positions by ELO descending (only players with matches)
  FOR r IN
    SELECT id, current_ranking, best_ranking
    FROM public.profiles
    WHERE elo_matches_played > 0
    ORDER BY elo_rating DESC, elo_matches_played DESC, created_at ASC
  LOOP
    pos := pos + 1;
    UPDATE public.profiles
    SET
      current_ranking = pos,
      best_ranking = CASE
        WHEN best_ranking IS NULL THEN pos
        WHEN pos < best_ranking THEN pos  -- lower number = better ranking
        ELSE best_ranking
      END
    WHERE id = r.id;
  END LOOP;
END;
$$;

-- ============================================
-- Function: Get user ranking position (real-time)
-- For users who haven't been ranked yet by the cron
-- ============================================
CREATE OR REPLACE FUNCTION public.get_user_ranking(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  user_elo INTEGER;
  ranking INTEGER;
BEGIN
  -- Get the user's ELO
  SELECT elo_rating INTO user_elo
  FROM public.profiles
  WHERE id = target_user_id;

  IF user_elo IS NULL THEN
    RETURN NULL;
  END IF;

  -- Count how many players have a higher ELO
  SELECT COUNT(*) + 1 INTO ranking
  FROM public.profiles
  WHERE elo_rating > user_elo
    AND elo_matches_played > 0;

  RETURN ranking;
END;
$$;

-- ============================================
-- Function: Update win/loss streak after match
-- Called from the rankings cron or trigger
-- ============================================
CREATE OR REPLACE FUNCTION public.update_player_streak(
  p_player_id UUID,
  p_won BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_won THEN
    UPDATE public.profiles
    SET
      win_streak = win_streak + 1,
      best_win_streak = GREATEST(best_win_streak, win_streak + 1),
      total_wins = total_wins + 1
    WHERE id = p_player_id;
  ELSE
    UPDATE public.profiles
    SET
      win_streak = 0,
      total_losses = total_losses + 1
    WHERE id = p_player_id;
  END IF;
END;
$$;

-- Run initial ranking calculation
SELECT public.recalculate_global_rankings();
