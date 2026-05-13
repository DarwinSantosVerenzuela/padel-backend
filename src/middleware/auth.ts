import { FastifyRequest, FastifyReply } from 'fastify';
import { supabase } from '../config/supabase.js';

export interface AuthenticatedRequest extends FastifyRequest {
    userId: string;
    accessToken: string;
}

export async function authMiddleware(
    request: FastifyRequest,
    reply: FastifyReply
): Promise<void> {
    const authHeader = request.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        reply.code(401).send({
            error: 'Unauthorized',
            message: 'Missing or invalid Authorization header'
        });
        return;
    }

    const token = authHeader.substring(7);

    try {
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            reply.code(401).send({
                error: 'Unauthorized',
                message: 'Invalid or expired token'
            });
            return;
        }

        // Attach user info to request
        (request as AuthenticatedRequest).userId = user.id;
        (request as AuthenticatedRequest).accessToken = token;
    } catch (err) {
        reply.code(500).send({
            error: 'Internal Server Error',
            message: 'Authentication service unavailable'
        });
    }
}
