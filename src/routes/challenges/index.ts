import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';
import { createNotification } from '../../services/push.js';

export async function challengesRoutes(app: FastifyInstance) {
    // Create challenge
    app.post('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({ challenged_id: z.string().uuid(), message: z.string().max(300).optional(), preferred_date: z.string().datetime().optional(), preferred_court_id: z.string().uuid().optional() }).parse(request.body);
        const client = createUserClient(req.accessToken);

        const [{ data: me }, { data: them }] = await Promise.all([
            client.from('profiles').select('elo_rating, display_name').eq('id', req.userId).single(),
            client.from('profiles').select('elo_rating').eq('id', body.challenged_id).single(),
        ]);

        const eloDiff = (me?.elo_rating || 1200) - (them?.elo_rating || 1200);
        const { data, error } = await client.from('challenges').insert({ challenger_id: req.userId, ...body, elo_diff: eloDiff }).select().single();
        if (error) throw new Error(error.message);

        await createNotification(body.challenged_id, 'challenge_received', '🏓 ¡Nuevo reto!', `${me?.display_name} te ha retado a jugar pádel`, { challenge_id: data.id });
        return { data };
    });

    // Get my challenges
    app.get('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { type = 'all' } = request.query as { type?: string };
        const client = createUserClient(req.accessToken);
        let query = client.from('challenges').select('*, challenger:profiles!challenger_id(id, username, display_name, avatar_url, elo_rating), challenged:profiles!challenged_id(id, username, display_name, avatar_url, elo_rating), court:courts(id, name, slug)').order('created_at', { ascending: false });
        if (type === 'received') query = query.eq('challenged_id', req.userId);
        else if (type === 'sent') query = query.eq('challenger_id', req.userId);
        else query = query.or(`challenger_id.eq.${req.userId},challenged_id.eq.${req.userId}`);
        const { data, error } = await query;
        if (error) throw new Error(error.message);
        return { data };
    });

    // Respond to challenge
    app.patch<{ Params: { challengeId: string } }>('/:challengeId', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { status } = z.object({ status: z.enum(['accepted', 'declined']) }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('challenges').update({ status }).eq('id', request.params.challengeId).eq('challenged_id', req.userId).select().single();
        if (error) throw new Error(error.message);

        if (data) {
            const notifType = status === 'accepted' ? 'challenge_accepted' : 'challenge_declined';
            await createNotification(data.challenger_id, notifType, status === 'accepted' ? '✅ Reto aceptado' : '❌ Reto rechazado', `Tu reto ha sido ${status === 'accepted' ? 'aceptado' : 'rechazado'}`, { challenge_id: data.id });
        }
        return { data };
    });
}
