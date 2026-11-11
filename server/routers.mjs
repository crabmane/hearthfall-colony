import { TRPCError } from '@trpc/server'
import mysql from 'mysql2/promise'
import { z } from 'zod'
import { router, protectedProcedure, publicProcedure } from './webdev-adapter.mjs'
import { leaderboard } from './leaderboard.mjs'
import { createLeaderboardRouter } from './leaderboard/router.mjs'
import { emitOwnerEvent } from './owner-notifier.mjs'

let savePool = null
function savesDb() {
  if (!savePool) {
    savePool = mysql.createPool({
      uri: process.env.DATABASE_URL,
      connectionLimit: 4,
      waitForConnections: true,
      connectTimeout: 5000,
      timezone: 'Z',
      dateStrings: true,
    })
  }
  return savePool
}

function userId(ctx) {
  const id = ctx?.user?.id
  if (!Number.isSafeInteger(id) || id < 1) {
    throw new TRPCError({ code: 'UNAUTHORIZED', message: 'account_session_required' })
  }
  return id
}

const slot = z.string().regex(/^[a-z0-9_-]{1,32}$/)
const saveMeta = z.object({
  slot,
  data: z.string().min(2).max(2_000_000),
  label: z.string().trim().min(1).max(80),
  day: z.number().int().min(0).max(100000),
  population: z.number().int().min(0).max(1000),
  mood: z.number().int().min(0).max(100),
}).strict()

const saves = router({
  list: protectedProcedure.query(async ({ ctx }) => {
    const uid = userId(ctx)
    const [rows] = await savesDb().execute(
      'SELECT slot,label,day,population,mood,OCTET_LENGTH(payload) AS bytes,created_at AS createdAt,updated_at AS updatedAt FROM game_cloud_saves WHERE user_id=? ORDER BY updated_at DESC LIMIT 10',
      [uid],
    )
    return {
      slots: rows.map((row) => ({
        slot: row.slot,
        label: row.label,
        day: Number(row.day),
        population: Number(row.population),
        mood: Number(row.mood),
        bytes: Number(row.bytes || 0),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      })),
    }
  }),

  get: protectedProcedure.input(z.object({ slot }).strict()).query(async ({ ctx, input }) => {
    const uid = userId(ctx)
    const [[row]] = await savesDb().execute(
      'SELECT slot,label,day,population,mood,payload,created_at AS createdAt,updated_at AS updatedAt FROM game_cloud_saves WHERE user_id=? AND slot=?',
      [uid, input.slot],
    )
    if (!row) throw new TRPCError({ code: 'NOT_FOUND', message: 'cloud_save_not_found' })
    return {
      slot: row.slot,
      label: row.label,
      day: Number(row.day),
      population: Number(row.population),
      mood: Number(row.mood),
      data: row.payload,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    }
  }),

  put: protectedProcedure.input(saveMeta).mutation(async ({ ctx, input }) => {
    const uid = userId(ctx)
    try {
      const parsed = JSON.parse(input.data)
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('invalid payload')
    } catch {
      throw new TRPCError({ code: 'BAD_REQUEST', message: 'invalid_save_payload' })
    }
    await savesDb().execute(
      'INSERT INTO game_cloud_saves (user_id,slot,label,day,population,mood,payload) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE label=VALUES(label),day=VALUES(day),population=VALUES(population),mood=VALUES(mood),payload=VALUES(payload)',
      [uid, input.slot, input.label, input.day, input.population, input.mood, input.data],
    )
    const [[row]] = await savesDb().execute(
      'SELECT updated_at AS updatedAt,OCTET_LENGTH(payload) AS bytes FROM game_cloud_saves WHERE user_id=? AND slot=?',
      [uid, input.slot],
    )
    void emitOwnerEvent({
      eventType: 'cloud_save_uploaded',
      severity: 'info',
      title: 'Cloud save uploaded',
      message: `Player uploaded save slot ${input.slot}.`,
      context: { slot: input.slot, day: input.day, population: input.population, bytes: Number(row?.bytes || 0) },
      user: ctx.user,
    })
    return { slot: input.slot, updatedAt: row?.updatedAt || null, bytes: Number(row?.bytes || 0) }
  }),

  delete: protectedProcedure.input(z.object({ slot }).strict()).mutation(async ({ ctx, input }) => {
    const uid = userId(ctx)
    const [result] = await savesDb().execute('DELETE FROM game_cloud_saves WHERE user_id=? AND slot=?', [uid, input.slot])
    return { deleted: Number(result.affectedRows || 0) > 0 }
  }),
})

const ownerEvent = z.object({
  eventType: z.enum(['new_player_account', 'cloud_save_failed', 'colony_game_over', 'severe_colony_alert', 'auth_error']),
  severity: z.enum(['info', 'warning', 'critical']).default('warning'),
  title: z.string().trim().min(1).max(160),
  message: z.string().trim().min(1).max(600),
  context: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
}).strict()

export const gameRouter = router({
  player: protectedProcedure.query(({ ctx }) => ({ id: ctx.user.id, name: ctx.user.name })),
  ownerEvent: protectedProcedure.input(ownerEvent).mutation(async ({ ctx, input }) => {
    const result = await emitOwnerEvent({ ...input, user: ctx.user })
    return { accepted: true, delivered: Boolean(result.delivered), deduplicated: Boolean(result.deduplicated) }
  }),
  saves,
  leaderboard: createLeaderboardRouter({ router, publicProcedure, protectedProcedure }, leaderboard),
})
