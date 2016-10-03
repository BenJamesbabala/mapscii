###
  termap - Terminal Map Viewer
  by Michael Strassburger <codepoet@cpan.org>

  UI and central command center
###

keypress = require 'keypress'
TermMouse = require 'term-mouse'

mercator = new (require('sphericalmercator'))()

Renderer = require './Renderer'
utils = require './utils'

module.exports = class Termap
  config:
    input: process.stdin
    output: process.stdout

    styleFile: __dirname+"/../styles/bright.json"
    zoomStep: 0.2

  width: null
  height: null
  canvas: null
  mouse: null

  mousePosition: [0, 0]
  mouseDragging: false

  degree: 0
  center:
    lat: 49.0189
    lon: 12.0990
    #lat: 0 #26.7
    #lon: 0 #20.2

  zoom: 0
  view: [0, 0]

  minZoom: null

  constructor: (options) ->
    @config[key] = val for key, val of options

    @_initKeyboard()
    @_initMouse()

    @_initRenderer()

  _initKeyboard: ->
    keypress @config.input
    @config.input.setRawMode true
    @config.input.resume()

    @config.input.on 'keypress', (ch, key) => @_onKey key

  _initMouse: ->
    @mouse = TermMouse input: @config.input, output: @config.output
    @mouse.start()

    @mouse.on 'click', (event) => @_onClick event
    @mouse.on 'scroll', (event) => @_onMouseScroll event
    @mouse.on 'move', (event) => @_onMouseMove event

  _initRenderer: ->
    @renderer = new Renderer @config.output
    @renderer.loadStyleFile @config.styleFile

    @config.output.on 'resize', =>
      @_resizeRenderer()
      @_draw()

    @_resizeRenderer()
    @zoom = @minZoom

  _resizeRenderer: (cb) ->
    @width = @config.output.columns >> 1 << 2
    @height = @config.output.rows * 4 - 4

    @minZoom = 4-Math.log(4096/@width)/Math.LN2

    @renderer.setSize @width, @height

  _onClick: (event) ->
    if @mouseDragging and event.button is "left"
      @view[0] -= (@mouseDragging.x-@mousePosition.x)<<1
      @view[1] -= (@mouseDragging.y-@mousePosition.y)<<2
      @_draw()

      @mouseDragging = false

  _onMouseScroll: (event) ->
    # TODO: handle .x/y for directed zoom
    @zoomBy @config.zoomStep * if event.button is "up" then -1 else 1
    @_draw()

  _onMouseMove: (event) ->
    # only continue if x/y are valid
    return unless event.x <= @config.output.columns and event.y <= @config.output.rows

    # start dragging
    if event.button is "left"
      if @mouseDragging
        @view[0] -= (@mouseDragging.x-event.x)<<1
        @view[1] -= (@mouseDragging.y-event.y)<<2

        if not @renderer.isDrawing and @renderer.lastDrawAt < Date.now()-100
          @_draw()
          @mouseDragging = x: event.x, y: event.y
      else
        @mouseDragging = x: event.x, y: event.y

    # update internal mouse tracker
    @mousePosition = x: event.x, y: event.y
    @renderer.notify @_getFooter()


  _onKey: (key) ->
    # check if the pressed key is configured
    draw = switch key?.name
      when "q"
        process.exit 0

      when "a" then @zoomBy @config.zoomStep
      when "z" then @zoomBy -@config.zoomStep

      when "k" then @degree += 15
      when "l" then @degree -= 15

      when "left" then @view[0] += 5
      when "right" then @view[0] -= 5
      when "up" then @view[1]+= 5
      when "down" then @view[1]-= 5

      else
        null

    if draw isnt null
      @_draw()
    else
      # display debug info for unhandled keys
      @renderer.notify JSON.stringify key


  _draw: ->
    @renderer.draw @view, @zoom, @degree
    @renderer.notify @_getFooter()

  _getTiles: ->

  _getBBox: (zoom = @zoom) ->
    [x, y] = utils.ll2xy @center.lon, @center.lat
    meterPerPixel = utils.metersPerPixel zoom, @center.lat

    width = @width * meterPerPixel
    height = @height * meterPerPixel

    west = x - width*.5
    east = x + width*.5
    south = y + height*.5
    north = y - height*.5

    box = mercator
    .inverse([west+1, south])
    .concat mercator.inverse([east-1, north])

  _tilesInBBox: (bbox, zoom = @zoom) ->
    tile = utils.ll2tile bbox[0], bbox[1], Math.floor zoom
    tiles =
      minX: Math.max 0, tile[0]
      minY: Math.max 0, tile[1]

    tile = utils.ll2tile bbox[2], bbox[3], Math.floor zoom
    tiles.maxX = Math.max 0, tile[0]
    tiles.maxY = Math.max 0, tile[1]

    tiles

  _getFooter: ->
    # features = @renderer.featuresAt @mousePosition.x-1-(@view[0]>>1), @mousePosition.y-1-(@view[1]>>2)
    # "features: ["+features.map((f) ->
    #   JSON.stringify
    #     name: f.feature.properties.name
    #     type: f.feature.properties.type
    #     rank: f.feature.properties.scalerank
    # ).join(", ")+"] "+
    # "#{@mousePosition.x} #{@mousePosition.y}"
    #"center: [#{utils.digits @center.lat, 2}, #{utils.digits @center.lng, 2}]}"
    bbox = @_getBBox()

    "zoom: #{utils.digits @zoom, 2} "+
    #{}"bbox: [#{bbox.map((z) -> utils.digits(z, 2)).join(', ')}]"+
    "tiles: "+(v for k,v of @_tilesInBBox(bbox) when typeof v is "number").join(",")


    #features.map((f) -> JSON.stringify f.feature.properties).join(" - ")

  zoomBy: (step) ->
    return @zoom = @minZoom if @zoom+step < @minZoom

    before = @zoom
    @zoom += step
