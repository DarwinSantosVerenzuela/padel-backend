import cron from 'node-cron';
import { processMatchmakingQueue, expireOldEntries } from '../services/matchmaking.js';

export function startMatchmakingCron() {
    // Process matchmaking queue every 30 seconds
    cron.schedule('*/30 * * * * *', async () => {
        try {
            const pairs = await processMatchmakingQueue();
            if (pairs.length > 0) {
                console.log(`✅ Matchmaking: ${pairs.length} pairs created`);
            }
        } catch (err) {
            console.error('❌ Matchmaking cron error:', err);
        }
    });

    // Expire old queue entries every 5 minutes
    cron.schedule('*/5 * * * *', async () => {
        try {
            const expired = await expireOldEntries();
            if (expired > 0) {
                console.log(`🕐 Expired ${expired} queue entries`);
            }
        } catch (err) {
            console.error('❌ Queue expiry cron error:', err);
        }
    });
}
