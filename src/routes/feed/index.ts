import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';

const createPostSchema = z.object({
    content: z.string().min(1).max(500),
    media_urls: z.array(z.string().url()).max(4).optional(),
    media_types: z.array(z.enum(['image', 'video'])).max(4).optional(),
    visibility: z.enum(['public', 'followers', 'private']).default('public'),
    match_id: z.string().uuid().optional(),
});

export async function feedRoutes(app: FastifyInstance) {
    // Get feed (timeline of followed users + own posts)
    app.get('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { cursor, limit = 20 } = request.query as { cursor?: string; limit?: number };
        const client = createUserClient(req.accessToken);

        let query = client
            .from('posts')
            .select(`
                *,
                author:profiles!author_id(id, username, display_name, avatar_url, is_verified),
                match:matches(id, score_team_a, score_team_b, court_id)
            `)
            .order('created_at', { ascending: false })
            .limit(Math.min(limit, 50));

        if (cursor) {
            query = query.lt('created_at', cursor);
        }

        const { data, error } = await query;
        if (error) throw new Error(error.message);

        return {
            data,
            cursor: data && data.length > 0 ? data[data.length - 1].created_at : null,
        };
    });

    // Create post
    app.post('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = createPostSchema.parse(request.body);
        const client = createUserClient(req.accessToken);

        const { data, error } = await client
            .from('posts')
            .insert({ ...body, author_id: req.userId })
            .select(`
                *,
                author:profiles!author_id(id, username, display_name, avatar_url, is_verified)
            `)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Get single post
    app.get<{ Params: { postId: string } }>('/:postId', async (request) => {
        const { postId } = request.params;
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);

        const { data, error } = await client
            .from('posts')
            .select(`
                *,
                author:profiles!author_id(id, username, display_name, avatar_url, is_verified),
                comments(
                    *,
                    author:profiles!author_id(id, username, display_name, avatar_url)
                )
            `)
            .eq('id', postId)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });

    // Delete post
    app.delete<{ Params: { postId: string } }>('/:postId', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { postId } = request.params;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('posts')
            .delete()
            .eq('id', postId)
            .eq('author_id', req.userId);

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Like post
    app.post<{ Params: { postId: string } }>('/:postId/like', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { postId } = request.params;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('likes')
            .insert({ user_id: req.userId, post_id: postId });

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Unlike post
    app.delete<{ Params: { postId: string } }>('/:postId/like', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { postId } = request.params;
        const client = createUserClient(req.accessToken);

        const { error } = await client
            .from('likes')
            .delete()
            .eq('user_id', req.userId)
            .eq('post_id', postId);

        if (error) throw new Error(error.message);
        return { success: true };
    });

    // Add comment
    app.post<{ Params: { postId: string } }>('/:postId/comments', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const { postId } = request.params;
        const { content, parent_id } = z.object({
            content: z.string().min(1).max(300),
            parent_id: z.string().uuid().optional(),
        }).parse(request.body);

        const client = createUserClient(req.accessToken);

        const { data, error } = await client
            .from('comments')
            .insert({ post_id: postId, author_id: req.userId, content, parent_id })
            .select(`
                *,
                author:profiles!author_id(id, username, display_name, avatar_url)
            `)
            .single();

        if (error) throw new Error(error.message);
        return { data };
    });
}
