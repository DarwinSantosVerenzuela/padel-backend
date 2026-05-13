import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';

const updateProfileSchema = z.object({
    display_name: z.string().min(1).max(100).optional(),
    bio: z.string().max(300).optional(),
    skill_level: z.enum(['beginner', 'intermediate', 'advanced', 'pro']).optional(),
    preferred_position: z.enum(['drive', 'reves', 'any']).optional(),
    dominant_hand: z.enum(['right', 'left']).optional(),
    locale: z.enum(['es', 'en']).optional(),
    city: z.string().max(100).optional(),
    country: z.string().max(50).optional(),
    notification_preferences: z.object({
        matches: z.boolean().optional(),
        chat: z.boolean().optional(),
        challenges: z.boolean().optional(),
        feed: z.boolean().optional(),
        sounds: z.boolean().optional(),
    }).optional(),
});

export async function usersRoutes(app: FastifyInstance) {
    // Get current user profile
    app.get('/me', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);

        const { data, error } = await client
            .from('profiles')
            .select('*')
            .eq('id', req.userId)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Get user by username
    app.get<{ Params: { username: string } }>('/:username', async (request) => {
        const { username } = request.params;
        const client = createUserClient(
            request.headers.authorization?.substring(7) || ''
        );

        const { data, error } = await client
            .from('profiles')
            .select(`
                id, username, display_name, avatar_url, bio,
                skill_level, preferred_position, dominant_hand,
                elo_rating, elo_matches_played, elo_confidence, elo_highest,
                city, country, is_verified, is_premium, is_online, last_seen_at,
                created_at
            `)
            .eq('username', username)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Update profile
    app.patch('/me', { preHandler: authMiddleware }, async (request, reply) => {
        const req = request as AuthenticatedRequest;
        const body = updateProfileSchema.parse(request.body);
        const client = createUserClient(req.accessToken);

        const { data, error } = await client
            .from('profiles')
            .update(body)
            .eq('id', req.userId)
            .select()
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Update location
    app.post('/me/location', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { latitude, longitude } = z.object({
            latitude: z.number().min(-90).max(90),
            longitude: z.number().min(-180).max(180),
        }).parse(request.body);

        const client = createUserClient(req.accessToken);

        const { error } = await client.rpc('update_user_location', {
            user_id: req.userId,
            lat: latitude,
            lng: longitude,
        });

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Get user stats
    app.get<{ Params: { userId: string } }>('/:userId/stats', async (request) => {
        const { userId } = request.params;
        const client = createUserClient(
            request.headers.authorization?.substring(7) || ''
        );

        const [
            { count: matchesPlayed },
            { count: wins },
            { count: followers },
            { count: following },
            { count: posts },
        ] = await Promise.all([
            client.from('match_players').select('*', { count: 'exact', head: true }).eq('player_id', userId),
            client.from('match_players').select('*', { count: 'exact', head: true }).eq('player_id', userId).not('elo_after', 'is', null),
            client.from('follows').select('*', { count: 'exact', head: true }).eq('following_id', userId),
            client.from('follows').select('*', { count: 'exact', head: true }).eq('follower_id', userId),
            client.from('posts').select('*', { count: 'exact', head: true }).eq('author_id', userId),
        ]);

        return {
            data: {
                matches_played: matchesPlayed || 0,
                wins: wins || 0,
                followers: followers || 0,
                following: following || 0,
                posts: posts || 0,
            }
        };
    });

    // Follow user
    app.post<{ Params: { userId: string } }>('/:userId/follow', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { userId } = request.params;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('follows')
            .insert({ follower_id: req.userId, following_id: userId });

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Unfollow user
    app.delete<{ Params: { userId: string } }>('/:userId/follow', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { userId } = request.params;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('follows')
            .delete()
            .eq('follower_id', req.userId)
            .eq('following_id', userId);

        if (error) throw new Error(error.message);
        return { success: true };
    });
}
