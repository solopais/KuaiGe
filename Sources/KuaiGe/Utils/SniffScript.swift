import Foundation

/// 注入到 WKWebView 的嗅探脚本（通用：拦截任意页面上真实播放的音频/视频资源）
enum SniffScript {
    /// 与 WKUserContentController.add(_:name:) 中的 name 保持一致
    static let handlerName = "sniff"

    /// 通用音频/视频 URL 匹配（只看「真媒体」，不再用 CDN 域名误判，避免把 .js 当音频）
    static let source: String = #"""
    (function () {
      if (window.__kgSniffInstalled) return;
      window.__kgSniffInstalled = true;

      // ========== 去重（同一 URL 只报告一次）==========
      var reported = {};

      function extOf(u) {
        try {
          var s = String(u).split('?')[0].split('#')[0].toLowerCase();
          var m = s.match(/\.([a-z0-9]+)$/);
          return m ? m[1] : '';
        } catch (e) { return ''; }
      }

      // 明显不是媒体的扩展名——即使出现在 <audio>/<video> 上也跳过
      var NON_MEDIA = ['js','mjs','css','html','htm','json','php','asp','aspx','jsp',
        'woff','woff2','ttf','otf','eot','png','jpg','jpeg','gif','svg','ico','webp',
        'xml','wasm','map','txt'];

      function isNonMediaExt(u) { return NON_MEDIA.indexOf(extOf(u)) !== -1; }

      // 真媒体扩展名（不含 .js/.css 等）
      function isMediaExt(u) {
        var e = extOf(u);
        if (!e || isNonMediaExt(u)) return false;
        return /^(mp3|m4a|aac|wav|flac|ogg|opus|wma|ape|amr|mp4|webm|mkv|avi|mov|ts|m3u8|m3u|f4m|mpd)$/.test(e);
      }

      // 是否应当作为媒体上报：blob 或 真媒体扩展名
      function isMediaUrl(u) {
        if (!u || typeof u !== 'string') return false;
        if (u.indexOf('blob:') === 0) return true;
        return isMediaExt(u);
      }

      function typeFromExt(u) {
        var e = extOf(u);
        if (/^(mp4|webm|mkv|avi|mov|ts|m3u8|m3u|f4m|mpd)$/.test(e)) return 'video';
        if (/^(mp3|m4a|aac|wav|flac|ogg|opus|wma|ape|amr)$/.test(e)) return 'audio';
        return 'other';
      }

      function typeFromContentType(ct) {
        ct = (ct || '').toLowerCase();
        if (ct.indexOf('video/') === 0) return 'video';
        if (ct.indexOf('audio/') === 0) return 'audio';
        if (/mpegurl/.test(ct)) return 'video';
        if (/x-m4a|ogg|webm|mp4|quicktime|flac|wav|aac|mp3/.test(ct)) return 'audio';
        return 'other';
      }

      function report(url, source, referer, mediaType) {
        try {
          if (!url || reported[url]) return;
          reported[url] = true;
          window.webkit.messageHandlers.__HANDLER__.postMessage({
            url: url,
            source: source,
            referer: referer || (document.location ? document.location.href : ''),
            mediaType: mediaType || 'other'
          });
        } catch (e) {}
      }

      // ========== 1) 拦截 <audio>/<video> 的 src 赋值 ==========
      try {
        var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (desc && desc.set) {
          var origSrcSet = desc.set;
          Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            configurable: true,
            get: desc.get,
            set: function (v) {
              try {
                if (typeof v === 'string' && v) {
                  var t = (this.tagName === 'VIDEO') ? 'video' : 'audio';
                  if (isMediaUrl(v)) {
                    var te = typeFromExt(v); if (te !== 'other') t = te;
                    report(v, 'media-src', document.referrer, t);
                  } else if (!isNonMediaExt(v)) {
                    // 媒体元素上挂了无扩展名的直链（如签名 URL），按元素类型上报
                    report(v, 'media-src', document.referrer, t);
                  }
                }
              } catch (e) {}
              return origSrcSet.call(this, v);
            }
          });
        }
      } catch (e) {}

      // ========== 2) 拦截 <source>/<audio>/<video> 的 src/srcset 属性 ==========
      try {
        var origSetAttr = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          try {
            if ((name === 'src' || name === 'srcset') &&
                (this.tagName === 'SOURCE' || this.tagName === 'AUDIO' || this.tagName === 'VIDEO')) {
              var val = (name === 'srcset') ? String(value).split(' ')[0] : value;
              if (typeof val === 'string' && val) {
                if (isMediaUrl(val)) report(val, 'source-attr', document.referrer, typeFromExt(val));
                else if (!isNonMediaExt(val)) report(val, 'source-attr', document.referrer, 'other');
              }
            }
          } catch (e) {}
          return origSetAttr.call(this, name, value);
        };
      } catch (e) {}

      // ========== 3) 拦截 fetch ==========
      try {
        var origFetch = window.fetch;
        window.fetch = function (input, init) {
          var url = (input && input.url) ? input.url
                   : (typeof input === 'string' ? input : '');
          var ref = '';
          try { ref = (init && init.headers && init.headers.get)
                        ? init.headers.get('Referer')
                        : (document.referrer || ''); } catch(e) {}
          // 请求 URL 本身带媒体扩展名才报（不会误报 .js）
          if (isMediaUrl(url)) report(url, 'fetch', ref, typeFromExt(url));
          return origFetch.apply(this, arguments).then(function (resp) {
            try {
              var ct = (resp && resp.headers && resp.headers.get)
                       ? resp.headers.get('Content-Type') : '';
              var mt = typeFromContentType(ct);
              if (mt !== 'other') report(url, 'fetch-resp', ref, mt);
            } catch (e) {}
            return resp;
          });
        };
      } catch (e) {}

      // ========== 4) 拦截 XMLHttpRequest ==========
      try {
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (m, url) {
          this.__kgUrl = url;
          return origOpen.apply(this, arguments);
        };
        var origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function () {
          var self = this;
          this.addEventListener('readystatechange', function () {
            try {
              if (self.readyState === 4) {
                var ct = (self.getResponseHeader && self.getResponseHeader('Content-Type')) || '';
                var mt = typeFromContentType(ct);
                if (isMediaUrl(self.__kgUrl) || mt !== 'other') {
                  report(self.__kgUrl, 'xhr', document.referrer,
                         mt !== 'other' ? mt : typeFromExt(self.__kgUrl));
                }
              }
            } catch (e) {}
          });
          return origSend.call(this);
        };
      } catch (e) {}

      // ========== 5) 拦截 blob URL 创建（很多平台用 blob 播放）==========
      try {
        var origCreateURL = URL.createObjectURL;
        URL.createObjectURL = function (blob) {
          var url = origCreateURL.apply(this, arguments);
          try {
            var bt = blob && blob.type ? blob.type : '';
            if (bt.indexOf('audio') !== -1) report(url, 'blob-audio', document.referrer, 'audio');
            else if (bt.indexOf('video') !== -1) report(url, 'blob-video', document.referrer, 'video');
          } catch (e) {}
          return url;
        };
      } catch (e) {}

      // ========== 6) 周期扫描已有媒体元素（含动态插入的）==========
      function scan() {
        try {
          var els = document.querySelectorAll('audio, video, source');
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var s = el.src || el.currentSrc || el.getAttribute('src');
            if (s && typeof s === 'string') {
              var t = (el.tagName === 'VIDEO') ? 'video' : 'audio';
              if (isMediaUrl(s)) {
                var te = typeFromExt(s); if (te !== 'other') t = te;
                report(s, 'media-element-scan', document.referrer, t);
              } else if (!isNonMediaExt(s) && s.indexOf('blob:') !== 0) {
                report(s, 'media-element-scan', document.referrer, t);
              }
            }
            if (el.querySelector) {
              var sources = el.querySelectorAll('source');
              for (var j = 0; j < sources.length; j++) {
                var ss = sources[j].src || sources[j].getAttribute('src');
                if (ss && typeof ss === 'string') {
                  if (isMediaUrl(ss)) report(ss, 'nested-source', document.referrer, typeFromExt(ss));
                  else if (!isNonMediaExt(ss) && ss.indexOf('blob:') !== 0) report(ss, 'nested-source', document.referrer, 'other');
                }
              }
            }
          }
        } catch (e) {}
      }
      scan();
      setInterval(scan, 1500);

      // ========== 7) 监听 DOM 变化（SPA 动态加载内容）==========
      try {
        var observer = new MutationObserver(function () { scan(); });
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'data-src', 'data-url']
        });
      } catch (e) {}

    })();
    """#

    /// 把脚本里的占位符替换成真实的 handler 名称
    static func build() -> String {
        source.replacingOccurrences(of: "__HANDLER__", with: handlerName)
    }
}
