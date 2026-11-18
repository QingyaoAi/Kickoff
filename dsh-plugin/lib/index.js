// Desktop receives workspace requests over the authenticated Host route. It also
// archives sessions and removes registrations for trashed Kickoff temp folders.

import { readFile, readdir, rm, stat } from 'node:fs/promises'
import { homedir } from 'node:os'
import { basename, isAbsolute, join } from 'node:path'

export const name = 'dsh-kickoff'

export const inject = ['workspaceRegistry']

const TEMP_FOLDER = /^tmp-\d{8}-\d{6}$/
const SWEEP_INTERVAL_MS = 60 * 60 * 1000
const DESKTOP_REQUESTS = join(homedir(), 'Library/Application Support/dev.kickoff.launcher/DeepSeek')
const REQUEST_FILE = /^\d+-[a-f0-9-]{36}\.request$/i
const REQUEST_LIFETIME_MS = 60 * 1000

function serveDesktopRequests(ctx) {
  ctx.inject(['connection'], (desktopCtx) => {
    desktopCtx.connection.fetch.register({
      path: '/api/kickoff/workspace',
      methods: ['GET', 'POST'],
      requestBody: 'buffered',
      async fetch(request) {
        if (request.method === 'POST') {
          const id = new URL(request.url).searchParams.get('id')
          if (!id || !REQUEST_FILE.test(id)) return new Response(null, { status: 400 })
          await rm(join(DESKTOP_REQUESTS, id), { force: true })
          return new Response(null, { status: 204 })
        }

        const ids = await readdir(DESKTOP_REQUESTS).catch(error => {
          if (error.code === 'ENOENT') return []
          throw error
        })
        for (const id of ids.filter(id => REQUEST_FILE.test(id)).sort()) {
          const file = join(DESKTOP_REQUESTS, id)
          try {
            const info = await stat(file)
            if (Date.now() - info.mtimeMs > REQUEST_LIFETIME_MS) {
              await rm(file, { force: true })
              continue
            }
            const path = await readFile(file, 'utf8')
            if (isAbsolute(path)) return Response.json({ id, path }, { headers: { 'cache-control': 'no-store' } })
            await rm(file, { force: true })
          } catch (error) {
            if (error.code !== 'ENOENT') throw error
          }
        }
        return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } })
      },
    })
  })
}

function sweepTempFolders(ctx) {
  const registry = ctx.workspaceRegistry
  let sweeping = false

  async function sweep() {
    if (sweeping) return
    sweeping = true
    try {
      for (const workspace of registry.list()) {
        if (!TEMP_FOLDER.test(basename(workspace.path))) continue
        if (await workspace.status() !== 'missing-dir') continue
        try {
          for (const sessionId of workspace.sessionIds) await registry.archiveSession(sessionId)
          await registry.delete(workspace.id)
        } catch (error) {
          // Usually a session that is still running; the next sweep tries again.
          console.warn(`[dsh-kickoff] kept ${workspace.path}: ${error instanceof Error ? error.message : error}`)
        }
      }
    } finally {
      sweeping = false
    }
  }

  ctx.effect(() => {
    void sweep()
    const timer = setInterval(() => { void sweep() }, SWEEP_INTERVAL_MS)
    return () => clearInterval(timer)
  })
}

export function apply(ctx) {
  if (ctx.get('profileContext')?.name !== 'desktop') return
  serveDesktopRequests(ctx)
  sweepTempFolders(ctx)
}
