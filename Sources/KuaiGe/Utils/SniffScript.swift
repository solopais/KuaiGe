import Foundation

/// 注入到 WKWebView 的嗅探脚本（通用：拦截页面里加载的音频文件，含 COS 远程链接）
enum SniffScript {
    /// 与 WKUserContentController.add(_:name:) 中的 name 保持一致
    static let handlerName = "sniff"

    static let source: String = """
    (function () {
      if (window.__kgSniffInstalled) return;
      window.__kgSniffInstalled = true;

      function isAudioUrl(u) {
        if (!u || typeof u !== 'string') return false;
        try {
          var s = u.toLowerCase();
          if (/\.(mp3|m4a|aac|wav|flac|ogg|opus|wma|m3u8|m3u)(\?|#|$)/.test(s)) return true;
          if (/myqcloud\.com|\.cos\.|aliyuncs\.com|\.oss[.-]|objectstorage|qiniucdn\.com|qbox\.me/.test(s)) return true;
          return false;
        } catch (e) { return false; }
      }

      function report(url, source, referer) {
        try {
          if (!url) return;
          window.webkit.messageHandlers.__HANDLER__.postMessage({
            url: url,
            source: source,
            referer: referer || ''
          });
        } catch (e) {}
      }

      // 1) 拦截 <audio>/<video> 的 src 赋值
      try {
        var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (desc && desc.set) {
          var orig = desc.set;
          Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            configurable: true,
            get: desc.get,
            set: function (v) {
              try { if (isAudioUrl(v)) report(v, 'media-src', document.referrer); } catch (e) {}
              return orig.call(this, v);
            }
          });
        }
      } catch (e) {}

      // 2) 拦截 fetch
      try {
        var origFetch = window.fetch;
        window.fetch = function (input, init) {
          var url = (input && input.url) ? input.url
                   : (typeof input === 'string' ? input : '');
          var ref = (init && init.headers && init.headers.get)
                    ? init.headers.get('Referer') : (document.referrer || '');
          if (isAudioUrl(url)) report(url, 'fetch', ref);
          return origFetch.apply(this, arguments).then(function (resp) {
            try {
              var ct = (resp && resp.headers && resp.headers.get)
                       ? resp.headers.get('Content-Type') : '';
              if (ct && /audio|mpegurl|octet|mp4|quicktime/.test(ct.toLowerCase())) {
                report(url, 'fetch-resp', ref);
              }
            } catch (e) {}
            return resp;
          });
        };
      } catch (e) {}

      // 3) 拦截 XMLHttpRequest
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
                if (isAudioUrl(self.__kgUrl) || /audio|mpegurl|octet|mp4|quicktime/.test(ct.toLowerCase())) {
                  report(self.__kgUrl, 'xhr', document.referrer);
                }
              }
            } catch (e) {}
          });
          return origSend.apply(this, arguments);
        };
      } catch (e) {}

      // 4) 周期扫描已有媒体元素
      function scan() {
        try {
          var els = document.querySelectorAll('audio, video, source');
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var s = el.src || el.currentSrc || el.getAttribute('src');
            if (s && isAudioUrl(s)) report(s, 'media-element', document.referrer);
          }
        } catch (e) {}
      }
      scan();
      setInterval(scan, 1500);
    })();
    """

    /// 把脚本里的占位符替换成真实的 handler 名称
    static func build() -> String {
        source.replacingOccurrences(of: "__HANDLER__", with: handlerName)
    }
}
