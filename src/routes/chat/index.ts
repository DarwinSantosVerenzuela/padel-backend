import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';

export async function chatRoutes(app: FastifyInstance) {
    // Get conversations
    app.get('/conversations', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('conversation_participants').select(`
            conversation:conversations(*, participants:conversation_participants(user:profiles(id, username, display_name, avatar_url, is_online)))
        `).eq('user_id', req.userId).order('created_at', { ascending: false });
        if (error) throw new Error(error.message);
        return { data };
    });

    // Get messages in conversation
    app.get<{ Params: { conversationId: string } }>('/conversations/:conversationId/messages', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { cursor, limit = 50 } = request.query as any;
        const client = createUserClient(req.accessToken);
        let query = client.from('messages').select('*, sender:profiles!sender_id(id, username, display_name, avatar_url)')
            .eq('conversation_id', request.params.conversationId).order('created_at', { ascending: false }).limit(Math.min(limit, 100));
        if (cursor) query = query.lt('created_at', cursor);
        const { data, error } = await query;
        if (error) throw new Error(error.message);
        return { data: data?.reverse(), cursor: data && data.length > 0 ? data[0].created_at : null };
    });

    // Send message
    app.post<{ Params: { conversationId: string } }>('/conversations/:conversationId/messages', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({ content: z.string().min(1).max(2000).optional(), media_url: z.string().url().optional(), media_type: z.enum(['text', 'image', 'video', 'audio', 'location', 'match_invite']).default('text'), reply_to_id: z.string().uuid().optional() }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('messages').insert({ conversation_id: request.params.conversationId, sender_id: req.userId, ...body }).select('*, sender:profiles!sender_id(id, username, display_name, avatar_url)').single();
        if (error) throw new Error(error.message);
        return { data };
    });

    // Create DM conversation
    app.post('/conversations', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { user_id } = z.object({ user_id: z.string().uuid() }).parse(request.body);
        const client = createUserClient(req.accessToken);

        // Check if DM already exists
        const { data: existing } = await client.rpc('find_existing_dm', { user_a: req.userId, user_b: user_id });
        if (existing && existing.length > 0) return { data: existing[0] };

        const { data: conv, error } = await client.from('conversations').insert({ type: 'direct' }).select().single();
        if (error) throw new Error(error.message);

        await client.from('conversation_participants').insert([
            { conversation_id: conv.id, user_id: req.userId, role: 'admin' },
            { conversation_id: conv.id, user_id: user_id, role: 'member' },
        ]);
        return { data: conv };
    });

    // Mark as read
    app.patch<{ Params: { conversationId: string } }>('/conversations/:conversationId/read', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const client = createUserClient(req.accessToken);
        await client.from('conversation_participants').update({ last_read_at: new Date().toISOString() })
            .eq('conversation_id', request.params.conversationId).eq('user_id', req.userId);
        return { success: true };
    });
}
