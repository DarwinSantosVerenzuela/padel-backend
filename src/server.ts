/**
 * PadelApp — Fastify Server Entry Point
 */

import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { env } from './config/env.js';

// Import route modules
import { authRoutes } from './routes/auth/index.js';
import { usersRoutes } from './routes/users/index.js';
import { feedRoutes } from './routes/feed/index.js';
import { matchesRoutes } from './routes/matches/index.js';
import { courtsRoutes } from './routes/courts/index.js';
import { chatRoutes } from './routes/chat/index.js';
import { challengesRoutes } from './routes/challenges/index.js';
import { rankingsRoutes } from './routes/rankings/index.js';
import { notificationsRoutes } from './routes/notifications/index.js';

// Import cron jobs
import { startMatchmakingCron } from './cron/matchmaking.js';
import { startRankingsCron } from './cron/rankings.js';

const app = Fastify({
    logger: {
        level: env.LOG_LEVEL,
        transport: env.NODE_ENV === 'development'
            ? { target: 'pino-pretty', options: { colorize: true } }
            : undefined,
    },
});

// ============================================
// PLUGINS
// ============================================

// CORS
await app.register(cors, {
    origin: env.CORS_ORIGIN.split(','),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept-Language'],
});

// Security headers
await app.register(helmet, {
    contentSecurityPolicy: env.NODE_ENV === 'production',
    crossOriginEmbedderPolicy: false,
});

// Rate limiting
await app.register(rateLimit, {
    max: env.RATE_LIMIT_MAX,
    timeWindow: env.RATE_LIMIT_WINDOW_MS,
    keyGenerator: (request) => {
        return request.headers['x-forwarded-for'] as string || request.ip;
    },
});

// ============================================
// HEALTH CHECK
// ============================================
app.get('/health', async () => ({
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: env.NODE_ENV,
    version: '1.0.0',
}));

// ============================================
// API ROUTES (versioned)
// ============================================
await app.register(async (api) => {
    api.register(authRoutes, { prefix: '/auth' });
    api.register(usersRoutes, { prefix: '/users' });
    api.register(feedRoutes, { prefix: '/feed' });
    api.register(matchesRoutes, { prefix: '/matches' });
    api.register(courtsRoutes, { prefix: '/courts' });
    api.register(chatRoutes, { prefix: '/chat' });
    api.register(challengesRoutes, { prefix: '/challenges' });
    api.register(rankingsRoutes, { prefix: '/rankings' });
    api.register(notificationsRoutes, { prefix: '/notifications' });
}, { prefix: '/api/v1' });

// ============================================
// ERROR HANDLER
// ============================================
app.setErrorHandler((error, request, reply) => {
    app.log.error(error);

    // Don't leak internal errors in production
    const statusCode = error.statusCode || 500;
    const message = statusCode === 500 && env.NODE_ENV === 'production'
        ? 'Internal Server Error'
        : error.message;

    reply.code(statusCode).send({
        error: error.name || 'Error',
        message,
        statusCode,
    });
});

// ============================================
// START SERVER
// ============================================
async function start() {
    try {
        await app.listen({ port: env.PORT, host: env.HOST });
        app.log.info(`🏓 PadelApp API running on ${env.HOST}:${env.PORT}`);
        app.log.info(`📌 Environment: ${env.NODE_ENV}`);

        // Start cron jobs
        if (env.NODE_ENV !== 'development' || process.env.ENABLE_CRONS === 'true') {
            startMatchmakingCron();
            startRankingsCron();
            app.log.info('⏰ Cron jobs started');
        }
    } catch (err) {
        app.log.fatal(err);
        process.exit(1);
    }
}

// Graceful shutdown
const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
for (const signal of signals) {
    process.on(signal, async () => {
        app.log.info(`${signal} received, shutting down gracefully...`);
        await app.close();
        process.exit(0);
    });
}

start();

export default app;
