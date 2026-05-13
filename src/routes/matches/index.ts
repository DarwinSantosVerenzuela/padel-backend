import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';

export async function matchesRoutes(app: FastifyInstance) {
    // Create match (manual)
    app.post('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({
            court_id: z.string().uuid().optional(),
            match_type: z.enum(['manual', 'random', 'challenge']),
            scheduled_at: z.string().datetime(),
            duration_minutes: z.number().min(30).max(180).default(90),
            is_competitive: z.boolean().default(true),
            payment_method: z.enum(['split', 'host_pays', 'winner_pays', 'free']).optional(),
            players: z.array(z.object({
                player_id: z.string().uuid(),
                team: z.enum(['a', 'b']),
                position: z.enum(['drive', 'reves']).optional(),
            })).min(1).max(4),
        }).parse(request.body);

        const client = createUserClient(req.accessToken);

        // Create match
        const { data: match, error: matchError } = await client
            .from('matches')
            .insert({
                court_id: body.court_id,
                match_type: body.match_type,
                scheduled_at: body.scheduled_at,
                duration_minutes: body.duration_minutes,
                is_competitive: body.is_competitive,
                payment_method: body.payment_method,
                created_by: req.userId,
            })
            .select()
            .single();

        if (matchError) throw new Error(matchError.message);

        // Add players
        const players = body.players.map(p => ({
            match_id: match.id,
            player_id: p.player_id,
            team: p.team,
            position: p.position,
        }));

        const { error: playersError } = await client
            .from('match_players')
            .insert(players);

        if (playersError) throw new Error(playersError.message);

        return { data: match };
    });

    // Join matchmaking queue (random)
    app.post('/queue', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({
            preferred_time_start: z.string().datetime().optional(),
            preferred_time_end: z.string().datetime().optional(),
            preferred_duration: z.number().min(30).max(180).default(90),
            max_distance_km: z.number().min(1).max(100).default(25),
            latitude: z.number().optional(),
            longitude: z.number().optional(),
        }).parse(request.body);

        const client = createUserClient(req.accessToken);

        // Get player's current ELO for range calculation
        const { data: profile } = await client
            .from('profiles')
            .select('elo_rating')
            .eq('id', req.userId)
            .single();

        const elo = profile?.elo_rating || 1200;

        const { data, error } = await client
            .from('matchmaking_queue')
            .insert({
                player_id: req.userId,
                preferred_time_start: body.preferred_time_start,
                preferred_time_end: body.preferred_time_end,
                preferred_duration: body.preferred_duration,
                max_distance_km: body.max_distance_km,
                elo_range_min: elo - 200,
                elo_range_max: elo + 200,
            })
            .select()
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Leave matchmaking queue
    app.delete('/queue', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('matchmaking_queue')
            .update({ status: 'cancelled' })
            .eq('player_id', req.userId)
            .eq('status', 'waiting');

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Submit match result
    app.patch<{ Params: { matchId: string } }>('/:matchId/result', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { matchId } = request.params;
        const body = z.object({
            score_team_a: z.string(),
            score_team_b: z.string(),
            winner_team: z.enum(['a', 'b']),
        }).parse(request.body);

        const client = createUserClient(req.accessToken);

        const { data, error } = await client
            .from('matches')
            .update({
                ...body,
                status: 'completed',
            })
            .eq('id', matchId)
            .eq('created_by', req.userId)
            .select()
            .single();

        if (error) throw new Error(error.message);

        // ELO calculation is triggered via a separate service/cron
        return { data };
    });

    // Get match details
    app.get<{ Params: { matchId: string } }>('/:matchId', async (request) => {
        const { matchId } = request.params;
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);

        const { data, error } = await client
            .from('matches')
            .select(`
                *,
                court:courts(id, name, slug, cover_image_url, city),
                players:match_players(
                    *,
                    profile:profiles(id, username, display_name, avatar_url, elo_rating)
                )
            `)
            .eq('id', matchId)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Get user's match history
    app.get('/history/:userId', async (request) => {
        const { userId } = request.params as { userId: string };
        const { cursor, limit = 20 } = request.query as { cursor?: string; limit?: number };
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);

        let query = client
            .from('match_players')
            .select(`
                *,
                match:matches(
                    *,
                    court:courts(id, name, slug, city)
                )
            `)
            .eq('player_id', userId)
            .order('created_at', { ascending: false })
            .limit(Math.min(limit, 50));

        if (cursor) query = query.lt('created_at', cursor);

        const { data, error } = await query;
        if (error) throw new Error(error.message);

        return {
            data,
            cursor: data && data.length > 0 ? data[data.length - 1].created_at : null,
        };
    });
}
