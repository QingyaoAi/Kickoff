// dsh-kickoff Desktop client bundle (ModuleLoader format).
// Wait for the initial workspace and session state before opening a task folder.

window.__ModuleLoader__.load({ id: 'dsh-kickoff', factory: function () {
  var module = { exports: {} }
  var exports = module.exports
  var DESKTOP_ROUTE = '/api/kickoff/workspace'

  function apply(ctx) {
    if (window.location.protocol !== 'dsh-app:') return

    var workspaces = ctx.get('workspaces')
    var sessions = ctx.get('sessions')
    var uiWorkspace = ctx.get('uiWorkspace')
    var lists = [workspaces.list, sessions.list]

    function listsReady() {
      return lists.every(function (list) { return list.getSnapshot().phase === 'ready' })
    }

    ctx.effect(function () {
      var controller = new AbortController()
      var signal = controller.signal
      var busy = false
      var completed = null

      async function poll() {
        if (signal.aborted || busy || document.hidden || !listsReady()) return
        busy = true
        try {
          if (!completed) {
            var response = await fetch(DESKTOP_ROUTE, { signal: signal })
            if (response.status === 204) return
            if (!response.ok) throw new Error('Could not read Kickoff request: ' + response.status)
            var request = await response.json()
            var workspace = await workspaces.create({ path: request.path })
            if (signal.aborted) return
            await uiWorkspace.openWorkspace(workspace.workspaceId)
            completed = request.id
          }
          var ack = await fetch(DESKTOP_ROUTE + '?id=' + encodeURIComponent(completed), {
            method: 'POST', signal: signal,
          })
          if (ack.ok) completed = null
        } catch (error) {
          if (!signal.aborted) console.warn('[dsh-kickoff] desktop request failed', error)
        } finally {
          busy = false
        }
      }

      var timer = window.setInterval(poll, 750)
      document.addEventListener('visibilitychange', poll)
      void poll()
      return function () {
        controller.abort()
        document.removeEventListener('visibilitychange', poll)
        window.clearInterval(timer)
      }
    })
  }

  exports.apply = apply
  exports.inject = ['workspaces', 'sessions', 'uiWorkspace']
  return module.exports
} })
