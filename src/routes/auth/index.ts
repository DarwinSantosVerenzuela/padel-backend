import { FastifyInstance } from 'fastify';

export async function authRoutes(app: FastifyInstance) {
    // Auth is handled by Supabase client-side
    // These endpoints handle server-side auth hooks

    // Webhook: Supabase Auth triggers on user signup
    app.post('/webhook/signup', async (request, reply) => {
        // Supabase Auth webhook — profile is auto-created via DB trigger
        return { received: true };
    });

    // Register push subscription
    app.post('/push-subscribe', async (request, reply) => {
        const authHeader = request.headers.authorization;
        if (!authHeader) {
            return reply.code(401).send({ error: 'Unauthorized' });
        }

        const { subscription } = request.body as { subscription: PushSubscription };

        const { createUserClient } = await import('../../config/supabase.js');
        const token = authHeader.substring(7);
        const client = createUserClient(token);

        const { data: { user } } = await client.auth.getUser(token);
        if (!user) return reply.code(401).send({ error: 'Invalid token' });

        await client
            .from('profiles')
            .update({ push_subscription: subscription })
            .eq('id', user.id);

        return { success: true };
    });
}
