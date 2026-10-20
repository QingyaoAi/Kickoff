// dsh-kickoff host half.
//
// 1. Sign-in URL for Kickoff. Kickoff opens dsh web in a browser that may have no dsh
//    sign-in cookie, for a server it didn't start (e.g. one started by the VS Code
//    extension), so it can't see the launch token that server printed. This writes the
//    token URL to <dsh home>/kickoff-web-url (mode 600, inside the 700 dsh home) while
//    the server runs, and removes it on shutdown.
//
// 2. Dead temp folders. Kickoff names unnamed task folders tmp-YYYYMMDD-HHmmss and its
//    05:00 job moves them to the Trash. Each one opened in dsh left a workspace whose
//    directory no longer exists, so the sidebar would fill up with dead tmp-* entries.
//    At startup and then every hour, such a workspace has its sessions archived (still
//    listed under "show archived") and its registration removed. Folders that still
//    exist, and every folder not named like a Kickoff temp folder, are left alone.

import { chmodSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join } from 'node:path'

export const name = 'dsh-kickoff'

export const inject = ['workspaceRegistry']

const URL_FILE = join(process.env.DSH_HOME?.trim() || join(homedir(), '.dsh'), 'kickoff-web-url')
const TEMP_FOLDER = /^tmp-\d{8}-\d{6}$/
const SWEEP_INTERVAL_MS = 60 * 60 * 1000

function publishSignInUrl(ctx) {
  ctx.inject(['connection', 'webApp'], (webCtx) => {
    let written
    let disposed = false
    // The origin is readable once the listener is bound; the Loader settling guarantees that.
    void Promise.resolve(webCtx.get('loader')?.await()).then(() => {
      if (disposed) return
      written = webCtx.connection.authenticatedUrl(webCtx.webApp.getAdvertisedUrl()) + '\n'
      writeFileSync(URL_FILE, written, { mode: 0o600 })
      chmodSync(URL_FILE, 0o600)
    }).catch((error) => {
      console.warn(`[dsh-kickoff] could not write ${URL_FILE}: ${error instanceof Error ? error.message : error}`)
    })
    webCtx.effect(() => () => {
      disposed = true
      try {
        // Another dsh web may have replaced it since.
        if (written !== undefined && readFileSync(URL_FILE, 'utf8') === written) rmSync(URL_FILE)
      } catch {}
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
  publishSignInUrl(ctx)
  sweepTempFolders(ctx)
}
