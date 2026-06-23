if ('undefined' === typeof FLUXIONSIGNALS) {
    var FLUXIONSIGNALS = {  };
};
if ('undefined' === typeof FLUXIONEVENTSOURCE) {
    var FLUXIONEVENTSOURCE = null;
};
if ('undefined' === typeof FLUXIONINITIALIZED) {
    var FLUXIONINITIALIZED = false;
};
if ('undefined' === typeof FLUXIONSSERECONNECTTIMER) {
    var FLUXIONSSERECONNECTTIMER = null;
};
if ('undefined' === typeof FLUXIONSSERETRYDELAY) {
    var FLUXIONSSERETRYDELAY = 1000;
};
if ('undefined' === typeof FLUXIONSSERETRYCOUNT) {
    var FLUXIONSSERETRYCOUNT = 0;
};
if ('undefined' === typeof FLUXIONSSEMAXRETRIES) {
    var FLUXIONSSEMAXRETRIES = 50;
};
if ('undefined' === typeof FLUXIONSSEBASEDELAY) {
    var FLUXIONSSEBASEDELAY = 1000;
};
if ('undefined' === typeof FLUXIONSSEMAXDELAY) {
    var FLUXIONSSEMAXDELAY = 30000;
};
if ('undefined' === typeof FLUXIONSSEWASCONNECTED) {
    var FLUXIONSSEWASCONNECTED = false;
};
if ('undefined' === typeof FLUXIONNAVIGATECALLBACKS) {
    var FLUXIONNAVIGATECALLBACKS = [];
};
/**
 * Register a CALLBACK to be invoked after SPA content navigation.
 * CALLBACK receives the container element that was updated.
 */
function fluxionOnNavigate(callback) {
    return FLUXIONNAVIGATECALLBACKS.push(callback);
};
/**
 * Notify Fluxion that SPA navigation has occurred on CONTAINER.
 * Re-binds actions and text bindings, then invokes registered callbacks.
 */
function fluxionNavigated(container) {
    fluxionBindActions(container);
    fluxionUpdateTextBindings();
    __PS_MV_REG = [];
    return FLUXIONNAVIGATECALLBACKS.forEach(function (cb) {
        return cb(container);
    });
};
/** Read the CSRF token from the meta tag in the page head. */
function fluxionGetCsrfToken() {
    var meta = document.querySelector('meta[name=fluxion-csrf]');
    return meta ? meta.getAttribute('content') : null;
};
/** Query a single element by CSS selector. */
function fluxionQs(selector) {
    return document.querySelector(selector);
};
/** Query all elements matching CSS selector. */
function fluxionQsa(selector) {
    return document.querySelectorAll(selector);
};
function fluxionGetSignal(name) {
    return FLUXIONSIGNALS[name];
};
function fluxionSetSignal(name, value) {
    return FLUXIONSIGNALS[name] = value;
};
function fluxionGetAllSignals() {
    var result = {  };
    for (var key in FLUXIONSIGNALS) {
        if (FLUXIONSIGNALS.hasOwnProperty(key)) {
            result[key] = FLUXIONSIGNALS[key];
        };
    };
    return result;
};
/** Replace the outerHTML of the element matching SELECTOR. */
function fluxionPatchReplace(selector, fragment) {
    var el = fluxionQs(selector);
    if (el) {
        el.outerHTML = fragment;
        __PS_MV_REG = [];
        return fluxionBindActions(fluxionQs(selector) || el.parentElement);
    };
};
/** Recursively morph OLD-NODE to match NEW-NODE, preserving focus and input state. */
function fluxionMorphNodes(oldNode, newNode) {
    if (!oldNode || !newNode) {
        return;
    };
    if (oldNode.nodeType !== newNode.nodeType || oldNode.nodeType === 1 && oldNode.tagName !== newNode.tagName) {
        oldNode.parentNode.replaceChild(newNode.cloneNode(true), oldNode);
        return;
    };
    if (oldNode.nodeType === 3 || oldNode.nodeType === 8) {
        if (oldNode.nodeValue !== newNode.nodeValue) {
            oldNode.nodeValue = newNode.nodeValue;
        };
        return;
    };
    if (oldNode.nodeType === 1) {
        fluxionSyncAttrs(oldNode, newNode);
        __PS_MV_REG = [];
        return fluxionMorphChildren(oldNode, newNode);
    };
};
/**
 * Synchronise attributes from NEW-EL onto OLD-EL.
 * Skips the value attribute on the currently focused element to preserve user input.
 * Also syncs the DOM value property on non-focused inputs so displayed values update
 * even after user interaction (setAttribute alone does not update the display).
 */
function fluxionSyncAttrs(oldEl, newEl) {
    var isFocused = oldEl === document.activeElement;
    var oldAttrs = {  };
    var i = 0;
    while (i < oldEl.attributes.length) {
        var attr = oldEl.attributes[i];
        oldAttrs[attr.name] = attr.value;
        ++i;
    };
    i = 0;
    while (i < newEl.attributes.length) {
        var attr1 = newEl.attributes[i];
        var name2 = attr1.name;
        var val = attr1.value;
        if (!(isFocused && name2 === 'value')) {
            if (oldEl.getAttribute(name2) !== val) {
                oldEl.setAttribute(name2, val);
            };
            if (name2 === 'value' && (oldEl.tagName === 'INPUT' || oldEl.tagName === 'TEXTAREA' || oldEl.tagName === 'SELECT') && oldEl.value !== val) {
                oldEl.value = val;
            };
        };
        delete oldAttrs[name2];
        ++i;
    };
    for (var name in oldAttrs) {
        if (oldAttrs.hasOwnProperty(name)) {
            oldEl.removeAttribute(name);
        };
    };
};
/** Morph the child nodes of OLD-EL to match those of NEW-EL. */
function fluxionMorphChildren(oldEl, newEl) {
    var oldChildren = oldEl.childNodes;
    var newChildren = newEl.childNodes;
    var i = 0;
    while (i < newChildren.length) {
        var newChild = newChildren[i];
        if (i < oldChildren.length) {
            var oldChild = oldChildren[i];
            if (oldChild.nodeType === 1 && newChild.nodeType === 1 && oldChild.tagName === newChild.tagName && oldChild.id && newChild.id && oldChild.id !== newChild.id) {
                oldEl.replaceChild(newChild.cloneNode(true), oldChild);
            } else {
                fluxionMorphNodes(oldChild, newChild);
            };
        } else {
            oldEl.appendChild(newChild.cloneNode(true));
        };
        ++i;
    };
    while (oldEl.childNodes.length > newChildren.length) {
        oldEl.removeChild(oldEl.lastChild);
    };
};
/**
 * Morph the element matching SELECTOR to match FRAGMENT.
 * Diffs the DOM trees and only updates what changed, preserving
 * focus, input values, and selection state on the active element.
 */
function fluxionPatchMorph(selector, fragment) {
    var oldEl = fluxionQs(selector);
    if (oldEl) {
        var template = document.createElement('template');
        template.innerHTML = fragment;
        var newEl = template.content.firstElementChild;
        if (newEl) {
            console.log('Fluxion morph:', selector, 'old-children=', oldEl.childNodes.length, 'new-children=', newEl.childNodes.length);
            fluxionMorphNodes(oldEl, newEl);
            __PS_MV_REG = [];
            return fluxionBindActions(oldEl);
        } else {
            __PS_MV_REG = [];
            return fluxionPatchReplace(selector, fragment);
        };
    } else {
        __PS_MV_REG = [];
        return console.log('Fluxion morph: element not found:', selector);
    };
};
/** Replace the innerHTML of the element matching SELECTOR. */
function fluxionPatchInner(selector, fragment) {
    var el = fluxionQs(selector);
    if (el) {
        el.innerHTML = fragment;
        __PS_MV_REG = [];
        return fluxionBindActions(el);
    };
};
/** Append FRAGMENT as the last child of the element matching SELECTOR. */
function fluxionAppendElement(selector, fragment) {
    var el = fluxionQs(selector);
    if (el) {
        el.insertAdjacentHTML('beforeend', fragment);
        __PS_MV_REG = [];
        return fluxionBindActions(el);
    };
};
/** Prepend FRAGMENT as the first child of the element matching SELECTOR. */
function fluxionPrependElement(selector, fragment) {
    var el = fluxionQs(selector);
    if (el) {
        el.insertAdjacentHTML('afterbegin', fragment);
        __PS_MV_REG = [];
        return fluxionBindActions(el);
    };
};
/** Remove the element matching SELECTOR from the DOM. */
function fluxionRemoveElement(selector) {
    var el = fluxionQs(selector);
    __PS_MV_REG = [];
    return el ? el.remove() : null;
};
function fluxionHandlePatch(data) {
    var selector1 = data.selector;
    var fragment2 = data.fragment;
    var mode3 = data.mode || 'morph';
    if (mode3 === 'morph') {
        __PS_MV_REG = [];
        return fluxionPatchMorph(selector1, fragment2);
    } else if (mode3 === 'replace') {
        __PS_MV_REG = [];
        return fluxionPatchReplace(selector1, fragment2);
    } else if (mode3 === 'inner') {
        __PS_MV_REG = [];
        return fluxionPatchInner(selector1, fragment2);
    } else {
        __PS_MV_REG = [];
        return fluxionPatchMorph(selector1, fragment2);
    };
};
function fluxionHandleRemove(data) {
    __PS_MV_REG = [];
    return fluxionRemoveElement(data.selector);
};
function fluxionHandleAppend(data) {
    __PS_MV_REG = [];
    return fluxionAppendElement(data.selector, data.fragment);
};
function fluxionHandlePrepend(data) {
    __PS_MV_REG = [];
    return fluxionPrependElement(data.selector, data.fragment);
};
function fluxionHandleSignals(data) {
    var signals4 = data.signals;
    if (signals4) {
        for (var key in signals4) {
            if (signals4.hasOwnProperty(key)) {
                fluxionSetSignal(key, signals4[key]);
            };
        };
        __PS_MV_REG = [];
        return fluxionUpdateTextBindings();
    };
};
function fluxionHandleScript(data) {
    var script5 = data.script;
    __PS_MV_REG = [];
    return script5 ? eval(script5) : null;
};
function fluxionHandleRedirect(data) {
    var url6 = data.url;
    return url6 ? (window.location.href = url6) : null;
};
/**
 * Send a POST request to URL with optional JSON BODY.
 * The response is expected to be text/event-stream (SSE).
 * Parses the SSE response and dispatches events.
 * Retries once on network error (status 0) from stale keep-alive.
 */
function fluxionPost(url, body, callback, retried) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('Accept', 'text/event-stream');
    var csrf = fluxionGetCsrfToken();
    if (csrf) {
        xhr.setRequestHeader('X-CSRF-Token', csrf);
    };
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                fluxionParseSseResponse(xhr.responseText);
                __PS_MV_REG = [];
                return callback ? callback() : null;
            } else if (xhr.status === 0 && !retried) {
                console.log('Fluxion: retrying POST', url);
                __PS_MV_REG = [];
                return fluxionPost(url, body, callback, true);
            } else {
                __PS_MV_REG = [];
                return fluxionShowError('Request failed (' + xhr.status + '): ' + url);
            };
        };
    };
    __PS_MV_REG = [];
    return xhr.send(body ? JSON.stringify(body) : '');
};
/** Parse an SSE text response and dispatch events. */
function fluxionParseSseResponse(text) {
    var blocks = text.split(/\n\n/);
    return blocks.forEach(function (block) {
        if (block && block.length > 0) {
            var eventType = null;
            var dataLines = [];
            var lines = block.split(/\n/);
            lines.forEach(function (line) {
                if (line.startsWith('event: ')) {
                    return eventType = line.substring(7);
                } else if (line.startsWith('data: ')) {
                    return dataLines.push(line.substring(6));
                };
            });
            if (eventType && dataLines.length > 0) {
                var dataStr = dataLines.join(String.fromCharCode(10));
                var data = JSON.parse(dataStr);
                __PS_MV_REG = [];
                return fluxionDispatchEvent(eventType, data);
            };
        };
    });
};
/** Dispatch a parsed SSE event to the appropriate handler. */
function fluxionDispatchEvent(eventType, data) {
    if (eventType === 'fluxion-patch') {
        __PS_MV_REG = [];
        return fluxionHandlePatch(data);
    } else if (eventType === 'fluxion-remove') {
        __PS_MV_REG = [];
        return fluxionHandleRemove(data);
    } else if (eventType === 'fluxion-append') {
        __PS_MV_REG = [];
        return fluxionHandleAppend(data);
    } else if (eventType === 'fluxion-prepend') {
        __PS_MV_REG = [];
        return fluxionHandlePrepend(data);
    } else if (eventType === 'fluxion-signals') {
        __PS_MV_REG = [];
        return fluxionHandleSignals(data);
    } else if (eventType === 'fluxion-script') {
        __PS_MV_REG = [];
        return fluxionHandleScript(data);
    } else if (eventType === 'fluxion-redirect') {
        __PS_MV_REG = [];
        return fluxionHandleRedirect(data);
    } else {
        __PS_MV_REG = [];
        return console.log('Fluxion: unknown event type:', eventType);
    };
};
/**
 * Collect data-param-* attributes from EL into an object.
 * E.g. data-param-id='42' becomes {id: '42'} in the result.
 */
function fluxionCollectParams(el) {
    var params = {  };
    var attrs = el.attributes;
    var i = 0;
    while (i < attrs.length) {
        var attr = attrs[i];
        if (attr.name.startsWith('data-param-')) {
            var key = attr.name.substring(11);
            params[key] = attr.value;
        };
        ++i;
    };
    return params;
};
/** Build the POST body: signals merged with element data-param-* attributes. */
function fluxionMergeBody(el) {
    var body = fluxionGetAllSignals();
    var params = fluxionCollectParams(el);
    for (var key in params) {
        if (params.hasOwnProperty(key)) {
            body[key] = params[key];
        };
    };
    __PS_MV_REG = [];
    return body;
};
/**
 * Scan for data-on-* attributes and bind event listeners.
 * ROOT defaults to document.
 */
function fluxionBindActions(root) {
    var root7 = root || document;
    var clickEls = root7.querySelectorAll('[data-on-click]');
    clickEls.forEach(function (el) {
        if (!el._fluxionClickBound) {
            el.addEventListener('click', function (e) {
                e.preventDefault();
                var actionUrl = el.getAttribute('data-on-click');
                var confirmMsg = el.getAttribute('data-confirm');
                var shouldDisable = el.hasAttribute('data-disable-during-request');
                if (!confirmMsg || window.confirm(confirmMsg)) {
                    if (shouldDisable) {
                        el.disabled = true;
                    };
                    __PS_MV_REG = [];
                    return fluxionPost(actionUrl, fluxionMergeBody(el), shouldDisable ? function () {
                        return el.disabled = false;
                    } : null);
                };
            });
            return el._fluxionClickBound = true;
        };
    });
    var submitEls = root7.querySelectorAll('[data-on-submit]');
    submitEls.forEach(function (el) {
        if (!el._fluxionSubmitBound) {
            el.addEventListener('submit', function (e) {
                e.preventDefault();
                var actionUrl = el.getAttribute('data-on-submit');
                var formData = new FormData(el);
                formData.forEach(function (value, key) {
                    __PS_MV_REG = [];
                    return fluxionSetSignal(key, value);
                });
                __PS_MV_REG = [];
                return fluxionPost(actionUrl, fluxionMergeBody(el));
            });
            return el._fluxionSubmitBound = true;
        };
    });
    var changeEls = root7.querySelectorAll('[data-on-change]');
    changeEls.forEach(function (el) {
        if (!el._fluxionChangeBound) {
            el.addEventListener('change', function (e) {
                e.preventDefault();
                var actionUrl = el.getAttribute('data-on-change');
                var body = fluxionMergeBody(el);
                if (el.type === 'checkbox') {
                    body['checked'] = el.checked ? 'true' : 'false';
                } else {
                    body['value'] = el.value;
                };
                __PS_MV_REG = [];
                return fluxionPost(actionUrl, body);
            });
            return el._fluxionChangeBound = true;
        };
    });
    var keydownEls = root7.querySelectorAll('[data-on-keydown]');
    keydownEls.forEach(function (el) {
        if (!el._fluxionKeydownBound) {
            var actionUrl = el.getAttribute('data-on-keydown');
            var keyFilter = el.getAttribute('data-key');
            el.addEventListener('keydown', function (e) {
                if (!keyFilter || e.key === keyFilter) {
                    e.preventDefault();
                    var body = fluxionMergeBody(el);
                    body['value'] = el.value;
                    __PS_MV_REG = [];
                    return fluxionPost(actionUrl, body);
                };
            });
            return el._fluxionKeydownBound = true;
        };
    });
    var inputEls = root7.querySelectorAll('[data-on-input]');
    inputEls.forEach(function (el) {
        if (!el._fluxionInputBound) {
            var actionUrl = el.getAttribute('data-on-input');
            var debounceMs = parseInt(el.getAttribute('data-debounce') || '0', 10);
            if (debounceMs && debounceMs > 0) {
                el.addEventListener('input', function (e) {
                    if (el._fluxionDebounceTimer) {
                        clearTimeout(el._fluxionDebounceTimer);
                    };
                    __PS_MV_REG = [];
                    return el._fluxionDebounceTimer = setTimeout(function () {
                        var body = fluxionMergeBody(el);
                        body['value'] = el.value;
                        __PS_MV_REG = [];
                        return fluxionPost(actionUrl, body);
                    }, debounceMs);
                });
            } else {
                el.addEventListener('input', function (e) {
                    var body = fluxionMergeBody(el);
                    body['value'] = el.value;
                    __PS_MV_REG = [];
                    return fluxionPost(actionUrl, body);
                });
            };
            __PS_MV_REG = [];
            return el._fluxionInputBound = true;
        };
    });
    var bindEls = root7.querySelectorAll('[data-bind]');
    return bindEls.forEach(function (el) {
        if (!el._fluxionBindBound) {
            var signalName = el.getAttribute('data-bind');
            var current = fluxionGetSignal(signalName);
            if (current !== undefined) {
                el.value = current;
            };
            el.addEventListener('input', function (e) {
                fluxionSetSignal(signalName, el.value);
                __PS_MV_REG = [];
                return fluxionUpdateTextBindings();
            });
            __PS_MV_REG = [];
            return el._fluxionBindBound = true;
        };
    });
};
/** Update all elements with data-text attribute from signal values. */
function fluxionUpdateTextBindings() {
    var textEls = document.querySelectorAll('[data-text]');
    return textEls.forEach(function (el) {
        var expr = el.getAttribute('data-text');
        var signalName = expr.startsWith('$') ? expr.substring(1) : expr;
        var value = fluxionGetSignal(signalName);
        __PS_MV_REG = [];
        return value !== undefined ? (el.textContent = value) : null;
    });
};
/** Show an error toast notification. Auto-dismisses after 8 seconds. */
function fluxionShowError(message) {
    console.warn('Fluxion error:', message);
    var existing = fluxionQs('#fluxion-error-toast');
    if (existing) {
        existing.remove();
    };
    var toast = document.createElement('div');
    toast.id = 'fluxion-error-toast';
    toast.innerHTML = '<span>' + message + '</span>' + '<button onclick=\"fluxionDismissError()\">&times;</button>';
    toast.style.cssText = 'position:fixed;bottom:1rem;right:1rem;max-width:28rem;' + 'background:#d9534f;color:#fff;padding:0.75rem 1rem;' + 'border-radius:6px;font-size:0.9rem;z-index:9999;' + 'display:flex;align-items:center;gap:0.75rem;' + 'box-shadow:0 4px 12px rgba(0,0,0,0.2);animation:fluxionFadeIn 0.2s';
    var btn = toast.querySelector('button');
    btn.style.cssText = 'background:none;border:none;color:#fff;font-size:1.2rem;cursor:pointer;padding:0;line-height:1';
    document.body.appendChild(toast);
    __PS_MV_REG = [];
    return setTimeout(function () {
        __PS_MV_REG = [];
        return fluxionDismissError();
    }, 8000);
};
/** Dismiss the error toast if present. */
function fluxionDismissError() {
    var toast = fluxionQs('#fluxion-error-toast');
    __PS_MV_REG = [];
    return toast ? toast.remove() : null;
};
/**
 * Show or update the connection status banner.
 * STATE is one of: reconnecting, lost, connected.
 */
function fluxionShowConnectionStatus(state, detail) {
    var banner = fluxionQs('#fluxion-connection-banner');
    if (state === 'connected') {
        if (banner) {
            banner.innerHTML = '<span>&#x2713; Reconnected</span>';
            banner.style.background = '#2d8a4e';
            setTimeout(function () {
                var b = fluxionQs('#fluxion-connection-banner');
                __PS_MV_REG = [];
                return b ? b.remove() : null;
            }, 2000);
        };
        __PS_MV_REG = [];
        return;
    };
    if (!banner) {
        banner = document.createElement('div');
        banner.id = 'fluxion-connection-banner';
        banner.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:10000;' + 'padding:6px 12px;font-size:0.8rem;font-family:sans-serif;' + 'text-align:center;color:#fff;transition:background 0.3s';
        document.body.appendChild(banner);
    };
    if (state === 'reconnecting') {
        banner.style.background = '#b87a1a';
        __PS_MV_REG = [];
        return banner.innerHTML = '<span>Connection lost. Reconnecting' + (detail ? ' in ' + detail + 's' : '') + '...</span>';
    } else if (state === 'lost') {
        banner.style.background = '#d9534f';
        __PS_MV_REG = [];
        return banner.innerHTML = '<span>Connection lost. </span>' + '<button onclick=\"fluxionReconnect()\" style=\"' + 'background:#fff;color:#d9534f;border:none;border-radius:4px;' + 'padding:2px 10px;margin-left:8px;cursor:pointer;font-size:0.8rem' + '\">Reconnect</button>';
    };
};
/** Compute the next retry delay with exponential backoff and jitter. */
function fluxionComputeRetryDelay() {
    var expDelay = FLUXIONSSEBASEDELAY * Math.pow(2, FLUXIONSSERETRYCOUNT);
    var capped = Math.min(expDelay, FLUXIONSSEMAXDELAY);
    var jitter = capped * (0.5 + Math.random() * 0.5);
    return Math.floor(jitter);
};
/** Schedule an SSE reconnection with exponential backoff. */
function fluxionScheduleReconnect() {
    if (FLUXIONSSERECONNECTTIMER) {
        clearTimeout(FLUXIONSSERECONNECTTIMER);
        FLUXIONSSERECONNECTTIMER = null;
    };
    if (FLUXIONSSERETRYCOUNT >= FLUXIONSSEMAXRETRIES) {
        console.error('Fluxion: gave up reconnecting after ' + FLUXIONSSEMAXRETRIES + ' attempts');
        __PS_MV_REG = [];
        return fluxionShowConnectionStatus('lost');
    } else {
        var delay = fluxionComputeRetryDelay();
        ++FLUXIONSSERETRYCOUNT;
        var secs = Math.ceil(delay / 1000);
        console.warn('Fluxion: reconnecting in ' + secs + 's (attempt ' + FLUXIONSSERETRYCOUNT + ')');
        fluxionShowConnectionStatus('reconnecting', secs);
        __PS_MV_REG = [];
        return FLUXIONSSERECONNECTTIMER = setTimeout(fluxionConnectSse, delay);
    };
};
/** Manual reconnect - resets retry state and connects immediately. */
function fluxionReconnect() {
    FLUXIONSSERETRYCOUNT = 0;
    FLUXIONSSERETRYDELAY = FLUXIONSSEBASEDELAY;
    __PS_MV_REG = [];
    return fluxionConnectSse();
};
/**
 * Open a persistent EventSource connection to /sse for server-push.
 * Uses exponential backoff with jitter on connection failure.
 */
function fluxionConnectSse() {
    if (FLUXIONEVENTSOURCE) {
        FLUXIONEVENTSOURCE.close();
        FLUXIONEVENTSOURCE = null;
    };
    if (FLUXIONSSERECONNECTTIMER) {
        clearTimeout(FLUXIONSSERECONNECTTIMER);
        FLUXIONSSERECONNECTTIMER = null;
    };
    var source = new EventSource('/sse');
    FLUXIONEVENTSOURCE = source;
    source.addEventListener('fluxion-patch', function (e) {
        var data8 = JSON.parse(e.data);
        console.log('Fluxion SSE: received patch for', data8.selector);
        __PS_MV_REG = [];
        return fluxionHandlePatch(data8);
    });
    source.addEventListener('fluxion-remove', function (e) {
        __PS_MV_REG = [];
        return fluxionHandleRemove(JSON.parse(e.data));
    });
    source.addEventListener('fluxion-append', function (e) {
        __PS_MV_REG = [];
        return fluxionHandleAppend(JSON.parse(e.data));
    });
    source.addEventListener('fluxion-prepend', function (e) {
        __PS_MV_REG = [];
        return fluxionHandlePrepend(JSON.parse(e.data));
    });
    source.addEventListener('fluxion-signals', function (e) {
        __PS_MV_REG = [];
        return fluxionHandleSignals(JSON.parse(e.data));
    });
    source.addEventListener('fluxion-script', function (e) {
        __PS_MV_REG = [];
        return fluxionHandleScript(JSON.parse(e.data));
    });
    source.addEventListener('fluxion-redirect', function (e) {
        __PS_MV_REG = [];
        return fluxionHandleRedirect(JSON.parse(e.data));
    });
    source.onopen = function () {
        console.log('Fluxion: SSE connection opened');
        if (FLUXIONSSEWASCONNECTED) {
            fluxionShowConnectionStatus('connected');
        };
        FLUXIONSSEWASCONNECTED = true;
        FLUXIONSSERETRYCOUNT = 0;
        __PS_MV_REG = [];
        return FLUXIONSSERETRYDELAY = FLUXIONSSEBASEDELAY;
    };
    __PS_MV_REG = [];
    return source.onerror = function () {
        source.close();
        FLUXIONEVENTSOURCE = null;
        __PS_MV_REG = [];
        return fluxionScheduleReconnect();
    };
};
/** Initialize the Fluxion client runtime. */
function fluxionInit() {
    if (FLUXIONINITIALIZED) {
        return;
    };
    FLUXIONINITIALIZED = true;
    console.log('Fluxion: initializing client runtime');
    fluxionBindActions();
    fluxionUpdateTextBindings();
    fluxionConnectSse();
    __PS_MV_REG = [];
    return console.log('Fluxion: ready');
};
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fluxionInit);
} else {
    fluxionInit();
};