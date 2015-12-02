http = require('http')

module.exports = (robot) ->

  watcherInterval = 5000
  watcherIntervalId = null

  watchList = []
  watchListFetchedAt = null

  mentions = ''
  mentionsFetchedAt = null

  deadHosts = {}

  robot.hear /watcher add (.*?)(?: as (.*?))?(?: port (.*?))?(?: path (.*?))?$/i, (res) ->
    unless res.match[1]
      res.send 'Bad request'
      return
    host =
      host: res.match[1]
      name: res.match[2] || res.match[1]
      port: res.match[3] || 80
      path: res.match[4] || '/'
    addHost(host, res)

  robot.hear /watcher loop/i, (res) ->
    if watcherIntervalId != null
      res.send 'Looping already'
    else
      res.send 'Starting watcher loop'
      watcherIntervalId = setInterval () ->
        hostsStatus res, true
      , watcherInterval

  robot.hear /watcher mention (.*)/i, (res) ->
    res.send 'Ok, will mention this guys: '+ res.match[1]
    robot.brain.set('hubot:watcher:mention', res.match[1])
    mentionsFetchedAt = null

  robot.hear /watcher status/i, (res) ->
    console.log 'Getting statuses'
    hostsStatus res, false

  robot.hear /watcher list/i, (res) ->
    console.log 'Getting watching list'
    hosts = fetchHosts()
    if hosts.length < 1
      res.send 'Nothing here'
      return
    for host in hosts
      res.send 'Watching '+ host.name + ' ( ' + host.host + ':' + host.port + host.path + ' )'

  robot.hear /watcher remove (.*)/i, (res) ->
    if rmHost(res.match[1])
      res.send 'Remove watcher for ' + res.match[1]

  fetchHosts = ->
    if !watchListFetchedAt || (new Date() - watchListFetchedAt) > 300000
      hostsData = (robot.brain.get('hubot:watcher') or "").split('|')
      hosts = []
      for hostData in hostsData
        match = hostData.match(/name:(.*),host:(.*),port:(.*),path:(.*)/)
        if match
          hosts.push({ name: match[1], host: match[2], port: match[3], path: match[4] })
      watchList = hosts
      watchListFetchedAt = new Date()
    watchList

  hostsStatus = (res, daemonize = false) ->
    for host in fetchHosts()
      notifyStatus(host, res, daemonize)

  notifyStatus = (host, res, daemonize = false) ->
    options = { method: 'HEAD', host: host.host, port: host.port, path: host.path }
    req = http.request options, (response) ->
      if response.statusCode == 200
        notifyAlive(host, res, daemonize)
      else
        notifyDead(host, res, daemonize)
    req.on('error', -> (error) -> notifyDead(host, res, daemonize) )
    req.end()

  notifyAlive = (host, res, daemonize = false) ->
    if cycles = deadHosts[host.name]
      delete deadHosts[host.name]
      res.send('*'+host.name+'*' + ' is back *alive* after ' + cycles + ' cycles')
    else if !daemonize
      res.send('*'+host.name+'*' + ' is *alive*')

  notifyDead = (host, res, daemonize = false) ->
    if !mentionsFetchedAt || (new Date() - mentionsFetchedAt) > 300000
      mentions = (robot.brain.get('hubot:watcher:mention') or '')
      mentionsFetchedAt = new Date()
    unless deadHosts[host.name]
      deadHosts[host.name] = 0
    cycles = deadHosts[host.name] += 1
    if !daemonize || cycles == 1 || (cycles % 10) == 0
      res.send('*'+host.name+'*' + ' is fucking *dead* for ' + cycles + ' cycles. ' + mentions)
  saveHosts = (hosts) ->
    output = []
    for host in hosts
      output.push([
        "name:" + host.name,
        "host:" + host.host,
        "port:" + host.port,
        "path:" + host.path
      ].join(','))
    if robot.brain.set('hubot:watcher', output.join('|'))
      watchListFetchedAt = null
      return true
    false

  addHost = (host, res) ->
    match = host.host.match(/(https?:\/\/)/)
    if match
      host.host = host.host.replace(match[1], '')
    hosts = fetchHosts()
    if hosts.filter((h) -> h.name == host.name).length > 0
      res.send host.name + ' already exists! Skipped.'
      return
    hosts.push(host)

    if saveHosts(hosts)
      res.send 'Watching '+ host.name + '(' + host.host + ':' + host.port + host.path + ')'
    else
      res.send 'Error while updating watchlist'

  rmHost = (name) ->
    hosts = fetchHosts().filter((host) -> host.name != name)
    if saveHosts(hosts)
      return true
    false
