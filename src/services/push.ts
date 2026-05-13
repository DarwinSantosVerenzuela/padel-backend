/**
 * PadelApp Web Push Notification Service
 */

import webpush from 'web-push';
import { env } from '../config/env.js';
import { supabaseAdmin } from '../config/supabase.js';

// Initialize VAPID keys
if (env.VAPID_PUBLIC_KEY && env.VAPID_PRIVATE_KEY && env.VAPID_SUBJECT) {
    webpush.setVapidDetails(
        env.VAPID_SUBJECT,
        env.VAPID_PUBLIC_KEY,
        env.VAPID_PRIVATE_KEY
    );
}

export interface PushPayload {
    title: string;
    body: string;
    icon?: string;
    badge?: string;
    tag?: string;
    data?: Record<string, unknown>;
    sound?: string;
    requireInteraction?: boolean;
}

/**
 * Send push notification to a specific user
 */
export async function sendPushToUser(
    userId: string,
    payload: PushPayload
): Promise<boolean> {
    try {
        // Get user's push subscription
        const { data: profile } = await supabaseAdmin
            .from('profiles')
            .select('push_subscription, notification_preferences')
            .eq('id', userId)
            .single();

        if (!profile?.push_subscription) {
            return false;
        }

        // Check notification preferences
        const prefs = profile.notification_preferences as Record<string, boolean>;
        if (payload.tag && prefs && prefs[payload.tag] === false) {
            return false; // User has disabled this notification type
        }

        const notificationPayload = JSON.stringify({
            title: payload.title,
            body: payload.body,
            icon: payload.icon || '/icons/icon-192x192.png',
            badge: payload.badge || '/icons/badge-72x72.png',
            tag: payload.tag,
            data: payload.data || {},
            requireInteraction: payload.requireInteraction || false,
        });

        await webpush.sendNotification(
            profile.push_subscription as webpush.PushSubscription,
            notificationPayload
        );

        return true;
    } catch (error: any) {
        // Handle expired subscriptions
        if (error.statusCode === 410 || error.statusCode === 404) {
            // Remove invalid subscription
            await supabaseAdmin
                .from('profiles')
                .update({ push_subscription: null })
                .eq('id', userId);
        }
        console.error(`Push notification failed for user ${userId}:`, error.message);
        return false;
    }
}

/**
 * Send push notification to multiple users
 */
export async function sendPushToUsers(
    userIds: string[],
    payload: PushPayload
): Promise<{ sent: number; failed: number }> {
    let sent = 0;
    let failed = 0;

    const promises = userIds.map(async (userId) => {
        const success = await sendPushToUser(userId, payload);
        if (success) sent++;
        else failed++;
    });

    await Promise.allSettled(promises);

    return { sent, failed };
}

/**
 * Create in-app notification + optional push
 */
export async function createNotification(
    userId: string,
    type: string,
    title: string,
    body: string,
    data: Record<string, unknown> = {},
    sendPush: boolean = true
): Promise<void> {
    // Create in-app notification
    await supabaseAdmin
        .from('notifications')
        .insert({
            user_id: userId,
            type,
            title,
            body,
            data,
            is_push_sent: sendPush,
        });

    // Send push notification
    if (sendPush) {
        await sendPushToUser(userId, {
            title,
            body,
            tag: type.split('_')[0], // e.g., 'match' from 'match_invite'
            data: { type, ...data },
        });
    }
}
