-- ============================================
-- PadelApp — Row Level Security Policies
-- Migration: 002_rls_policies
-- CRITICAL: All tables MUST have RLS enabled
-- ============================================

-- ============================================
-- PROFILES
-- ============================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles are viewable by everyone"
    ON public.profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================
-- FOLLOWS
-- ============================================
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Follows are viewable by everyone"
    ON public.follows FOR SELECT
    USING (true);

CREATE POLICY "Users can follow others"
    ON public.follows FOR INSERT
    WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can unfollow"
    ON public.follows FOR DELETE
    USING (auth.uid() = follower_id);

-- ============================================
-- COURTS
-- ============================================
ALTER TABLE public.courts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active courts are viewable by everyone"
    ON public.courts FOR SELECT
    USING (is_active = true);

CREATE POLICY "Court owners can insert"
    ON public.courts FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Court owners can update"
    ON public.courts FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- ============================================
-- COURT MENU CATEGORIES
-- ============================================
ALTER TABLE public.court_menu_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Menu categories viewable by everyone"
    ON public.court_menu_categories FOR SELECT
    USING (true);

CREATE POLICY "Court owners can manage categories"
    ON public.court_menu_categories FOR INSERT
    WITH CHECK (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

CREATE POLICY "Court owners can update categories"
    ON public.court_menu_categories FOR UPDATE
    USING (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

CREATE POLICY "Court owners can delete categories"
    ON public.court_menu_categories FOR DELETE
    USING (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

-- ============================================
-- COURT MENU ITEMS
-- ============================================
ALTER TABLE public.court_menu_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Menu items viewable by everyone"
    ON public.court_menu_items FOR SELECT
    USING (true);

CREATE POLICY "Court owners can manage items"
    ON public.court_menu_items FOR INSERT
    WITH CHECK (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

CREATE POLICY "Court owners can update items"
    ON public.court_menu_items FOR UPDATE
    USING (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

CREATE POLICY "Court owners can delete items"
    ON public.court_menu_items FOR DELETE
    USING (
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

-- ============================================
-- COURT REVIEWS
-- ============================================
ALTER TABLE public.court_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Reviews viewable by everyone"
    ON public.court_reviews FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can review"
    ON public.court_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own review"
    ON public.court_reviews FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own review"
    ON public.court_reviews FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================
-- BOOKINGS
-- ============================================
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own bookings"
    ON public.bookings FOR SELECT
    USING (
        auth.uid() = booked_by OR
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

CREATE POLICY "Authenticated users can book"
    ON public.bookings FOR INSERT
    WITH CHECK (auth.uid() = booked_by);

CREATE POLICY "Users can update own bookings"
    ON public.bookings FOR UPDATE
    USING (
        auth.uid() = booked_by OR
        auth.uid() = (SELECT owner_id FROM public.courts WHERE id = court_id)
    );

-- ============================================
-- MATCHES
-- ============================================
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Matches viewable by participants and public competitive"
    ON public.matches FOR SELECT
    USING (
        is_competitive = true OR
        auth.uid() = created_by OR
        auth.uid() IN (SELECT player_id FROM public.match_players WHERE match_id = id)
    );

CREATE POLICY "Authenticated users can create matches"
    ON public.matches FOR INSERT
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Match creator can update"
    ON public.matches FOR UPDATE
    USING (auth.uid() = created_by);

-- ============================================
-- MATCH PLAYERS
-- ============================================
ALTER TABLE public.match_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Match players viewable by anyone"
    ON public.match_players FOR SELECT
    USING (true);

CREATE POLICY "Match creator can add players"
    ON public.match_players FOR INSERT
    WITH CHECK (
        auth.uid() = (SELECT created_by FROM public.matches WHERE id = match_id)
        OR auth.uid() = player_id
    );

CREATE POLICY "Players can update own status"
    ON public.match_players FOR UPDATE
    USING (auth.uid() = player_id);

-- ============================================
-- MATCHMAKING QUEUE
-- ============================================
ALTER TABLE public.matchmaking_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own queue entries"
    ON public.matchmaking_queue FOR SELECT
    USING (auth.uid() = player_id);

CREATE POLICY "Users can join queue"
    ON public.matchmaking_queue FOR INSERT
    WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Users can update own queue entry"
    ON public.matchmaking_queue FOR UPDATE
    USING (auth.uid() = player_id);

CREATE POLICY "Users can leave queue"
    ON public.matchmaking_queue FOR DELETE
    USING (auth.uid() = player_id);

-- ============================================
-- CHALLENGES
-- ============================================
ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view challenges involving them"
    ON public.challenges FOR SELECT
    USING (auth.uid() = challenger_id OR auth.uid() = challenged_id);

CREATE POLICY "Users can create challenges"
    ON public.challenges FOR INSERT
    WITH CHECK (auth.uid() = challenger_id);

CREATE POLICY "Challenged user can respond"
    ON public.challenges FOR UPDATE
    USING (auth.uid() = challenged_id);

-- ============================================
-- POSTS
-- ============================================
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public posts viewable by all"
    ON public.posts FOR SELECT
    USING (
        visibility = 'public'
        OR author_id = auth.uid()
        OR (visibility = 'followers' AND author_id IN (
            SELECT following_id FROM public.follows WHERE follower_id = auth.uid()
        ))
    );

CREATE POLICY "Authenticated users can post"
    ON public.posts FOR INSERT
    WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own posts"
    ON public.posts FOR UPDATE
    USING (auth.uid() = author_id);

CREATE POLICY "Authors can delete own posts"
    ON public.posts FOR DELETE
    USING (auth.uid() = author_id);

-- ============================================
-- COMMENTS
-- ============================================
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Comments viewable by everyone"
    ON public.comments FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can comment"
    ON public.comments FOR INSERT
    WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own comments"
    ON public.comments FOR UPDATE
    USING (auth.uid() = author_id);

CREATE POLICY "Authors can delete own comments"
    ON public.comments FOR DELETE
    USING (auth.uid() = author_id);

-- ============================================
-- LIKES
-- ============================================
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Likes viewable by everyone"
    ON public.likes FOR SELECT
    USING (true);

CREATE POLICY "Users can like"
    ON public.likes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can unlike"
    ON public.likes FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================
-- CONVERSATIONS
-- ============================================
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can view conversations"
    ON public.conversations FOR SELECT
    USING (
        id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    );

CREATE POLICY "Authenticated users can create conversations"
    ON public.conversations FOR INSERT
    WITH CHECK (true);

-- ============================================
-- CONVERSATION PARTICIPANTS
-- ============================================
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can view members"
    ON public.conversation_participants FOR SELECT
    USING (
        conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    );

CREATE POLICY "Users can add participants"
    ON public.conversation_participants FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Users can update own participation"
    ON public.conversation_participants FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================
-- MESSAGES
-- ============================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can view messages"
    ON public.messages FOR SELECT
    USING (
        conversation_id IN (
            SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Participants can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id AND
        conversation_id IN (
            SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Senders can update own messages"
    ON public.messages FOR UPDATE
    USING (auth.uid() = sender_id);

-- ============================================
-- NOTIFICATIONS
-- ============================================
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "System can create notifications"
    ON public.notifications FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Users can update own notifications"
    ON public.notifications FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notifications"
    ON public.notifications FOR DELETE
    USING (auth.uid() = user_id);
