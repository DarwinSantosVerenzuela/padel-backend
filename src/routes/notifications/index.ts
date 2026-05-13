import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';

export async function notificationsRoutes(app: FastifyInstance) {
    app.get('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { limit = 30, unread_only } = request.query as any;
        const client = createUserClient(req.accessToken);
        let query = client.from('notifications').select('*').eq('user_id', req.userId).order('created_at', { ascending: false }).limit(limit);
        if (unread_only === 'true') query = query.eq('is_read', false);
        const { data, error } = await query;
        if (error) throw new Error(error.message);
        return { data };
    });

    app.patch('/read-all', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);
        await client.from('notifications').update({ is_read: true }).eq('user_id', req.userId).eq('is_read', false);
        return { success: true };
    });

    app.patch<{ Params: { id: string } }>('/:id/read', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);
        await client.from('notifications').update({ is_read: true }).eq('id', request.params.id).eq('user_id', req.userId);
        return { success: true };
    });
}
