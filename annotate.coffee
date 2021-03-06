window.indexedDB = window.indexedDB || window.mozIndexedDB || window.webkitIndexedDB || window.msIndexedDB

DB_NAME = "laura-annotations"
STORE_NAME = "annotations"

upload_url = "/annotation"


String.prototype.hashCode = -> 
  hash = 0
  if this.length == 0
      return hash
  for _,i in this
    chr = this.charCodeAt(i)
    hash  = ((hash << 5) - hash) + chr
    hash |= 0   # Convert to 32bit integer
  return hash

db = null

# annotations[ann_id] = [element ids]
annotations = {}
states = ['not-relevant', 'none', 'relevant']

set_annotation = (ev) ->
    el = $(this)
    ann_id = parseInt(el.attr("data-ann-id"))
    val = el.val()
    fields = annotations[ann_id].fields
    $("input[value=#{val}]", $(fields)).prop("checked", true)

    objectStore = db.transaction([STORE_NAME], "readwrite").objectStore(STORE_NAME)
    req = objectStore.put {
        'ann_id': ann_id,
        rel: val
        query: annotations[ann_id].query
        item: annotations[ann_id].item
    }
    req.onerror = (ev) -> console.log("Failed to set annotataion: "+req.error)
    req.onsuccess = (ev) -> console.log("Set annotation "+ann_id+" to "+val)
        
add_annotations = ->
    $(".annotation").each (i) -> 
        el = $(this)
        ann_id = (el.data('query') + el.data('item')).hashCode()
        if not annotations[ann_id]
            annotations[ann_id] = {
                query: el.data('query'),
                item: el.data('item')
                fields: []
            }

        el.append($('<label>', {'for': "ann-\"#{i}\"-not-relevant"}).html('-'))
        for _, state of states
            do (state) ->
                opt = $("<input>", {
                    type: "radio",
                    name: "group-#{i}",
                    value: state,
                    'data-ann-id': ann_id,
                })
                opt.click set_annotation
                el.append opt
        el.append($('<label>', {'for': "ann-\"#{i}\"-relevant"}).html('+'))
        annotations[ann_id].fields.push el[0]

 
add_toolbar = ->
    div = $("<div>").attr('id', 'toolbar').addClass("toolbar")
    status = $("<span>")
    div.append status

    sess = $("<input>", {
        id: "session-name",
        placeholder: "Session name",
        })
    sess.change (ev) ->
        sessionStorage.setItem("session-name", $(this).val())
    sess.val(sessionStorage.getItem("session-name"))
    div.append sess

    export_btn = $("<button>Export</button>")
    div.append export_btn
    export_btn.click ->
        generate_qrel (qrel) ->
            $("#qrel").remove()
            area = $("<textarea>", {id: "qrel"}).html(qrel)
            area.css('width', '50em')
            $("#toolbar").after area

    upload_btn = $("<button>Upload</button>")
    div.append upload_btn
    upload_btn.click ->
        generate_qrel (qrel) ->
            passwd = window.prompt("Password?");
            $.ajax(upload_url, {
                type: "POST",
                data: {
                    "user": $("#session-name").val(),
                    "password": passwd,
                    "qrel": qrel,
                },
            });

    clear_btn = $("<button>Clear</button>")
    clear_btn.click ->
        req = db
            .transaction([STORE_NAME], "readwrite")
            .objectStore(STORE_NAME)
            .clear()
        req.onsuccess = ->
            console.log("Clear successful")
            $("input").attr("checked", false)
        req.onerror = -> console.log("Clear failed: "+req.error)

    div.append clear_btn

    $("body").prepend div

generate_qrel = (on_done) ->
    objectStore = db.transaction([STORE_NAME], "readonly").objectStore(STORE_NAME)
    accum = ""
    req = objectStore.openCursor()
    sess = $("#session-name").val()
    if sess == ""
        sess = "0"
    req.onsuccess = (ev) ->
        cursor = ev.target.result
        if cursor
            val = cursor.value
            rel = switch val.rel
                when 'not-relevant' then 0
                when 'relevant' then 1
                else null
            if rel isnt null
                accum = accum + "#{val.query}\t#{sess}\t#{val.item}\t#{rel}\n"
            cursor.continue()
        else
            on_done accum

load_existing_annotations = ->
    for ann_id,ann of annotations
        do (ann_id, ann) -> 
            ann_id = parseInt(ann_id)
            objectStore = db.transaction([STORE_NAME], "readonly").objectStore(STORE_NAME)
            req = objectStore.get(ann_id)
            req.onsuccess = (ev) ->
                if ev.target.result
                    rel = ev.target.result.rel
                    $("input[value=#{rel}]", ann.fields).attr('checked', true)

delay = (ms, func) -> setTimeout func, ms

notify = (msg, klass) ->
    el = $('<li>').html(msg)
    el.addClass(klass)
    $("#notifications").append el
    delay 5000, () -> el.fadeOut()

$(document).ready ->
    add_toolbar()
    add_annotations()

    $("head").append $("<style>
        #notifications { float: right; list-style: none; }
        #notifications li { border-radius: 1em; margin: 1em; padding: 2em; }
        #notifications li.fail { background-color: #fdd; }
        #notifications li.success { background-color: #ded; }
        </style>")
    notifications = $('<ul id="notifications"></ul>')
    notifications = $("body").prepend notifications

    req = window.indexedDB.open(DB_NAME, 4)
    req.onsuccess = (ev) ->
        db = this.result
        load_existing_annotations()

    req.onupgradeneeded = (ev) ->
        db = ev.target.result
        db.createObjectStore(STORE_NAME, { keyPath: "ann_id" })

$(document).ajaxError (ev, resp) -> notify(resp.responseText, 'fail')
$(document).ajaxSuccess (ev, resp) -> notify("annotation successfully saved", 'success')
