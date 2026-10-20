// dsh-kickoff client bundle (ModuleLoader format)
//
// Kickoff opens dsh web as  http://127.0.0.1:3080/#kickoff-open=<percent-encoded folder path>.
// The fragment never reaches the server and survives the launch-token redirect. This
// plugin removes it from the address bar, registers the folder as a workspace (a no-op
// when it already is one) and opens a session there, as "Add workspace" would.
//
// It waits until the workspace and session lists have loaded, so the page's own
// restoration of the last session runs first and this navigation replaces it.

window.__ModuleLoader__.load({ id: 'dsh-kickoff', factory: function (require) {
  var module = { exports: {} }
  var exports = module.exports

  var PARAM = 'kickoff-open'

  /** Takes the folder path out of the URL fragment, so a reload or a copied URL doesn't open it again. */
  function takeFolder() {
    if (window.location.hash.length < 2) return null
    var params = new URLSearchParams(window.location.hash.slice(1))
    var path = params.get(PARAM)
    if (!path) return null
    params.delete(PARAM)
    var rest = params.toString()
    window.history.replaceState(window.history.state, '',
      window.location.pathname + window.location.search + (rest ? '#' + rest : ''))
    return path
  }

  function apply(ctx) {
    var workspaces = ctx.get('workspaces')
    var sessions = ctx.get('sessions')
    var uiWorkspace = ctx.get('uiWorkspace')
    var lists = [workspaces.list, sessions.list]
    var queued = []
    var unsubscribers = []

    function listsReady() {
      return lists.every(function (list) { return list.getSnapshot().phase === 'ready' })
    }

    function openFolder(path) {
      workspaces.create({ path: path })
        .then(function (workspace) { return uiWorkspace.openWorkspace(workspace.workspaceId) })
        .catch(function (error) { console.warn('[dsh-kickoff] could not open ' + path, error) })
    }

    function flush() {
      if (!listsReady()) return
      unsubscribers.forEach(function (stop) { stop() })
      unsubscribers = []
      queued.splice(0).forEach(openFolder)
    }

    function check() {
      var path = takeFolder()
      if (!path) return
      queued.push(path)
      if (unsubscribers.length === 0) {
        unsubscribers = lists.map(function (list) { return list.subscribe(flush) })
      }
      flush()
    }

    ctx.effect(function () {
      check()
      window.addEventListener('hashchange', check)
      return function () {
        window.removeEventListener('hashchange', check)
        unsubscribers.forEach(function (stop) { stop() })
        unsubscribers = []
      }
    })
  }

  exports.apply = apply
  exports.inject = ['workspaces', 'sessions', 'uiWorkspace']
  return module.exports
} })
