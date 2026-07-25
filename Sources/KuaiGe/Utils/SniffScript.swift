import Foundation

/// 注入到 WKWebView 的嗅探脚本 —— 浏览器扩展级通用媒体资源提取
///
/// 设计原则（对标 Chrome/Firefox 媒体嗅探扩展）：
/// 1. 不依赖任何特定域名/CDN，纯通用匹配
/// 2. 多层拦截：DOM 元素 + fetch/XHR + blob + Performance API 兜底
/// 3. 按 Content-Type / 扩展名 / 元素标签三重判断是否为真媒体
/// 4. 自动去重，同一 URL 只报告一次
enum SniffScript {
    /// 与 WKUserContentController.add(_:name:) 中的 name 保持一致
    static let handlerName = "sniff"

    /// 完整的浏览器扩展级嗅探脚本
    static let source: String = #"""
    (function(){
      if (window.__kgSniffInstalled) return;
      window.__kgSniffInstalled = true;
      console.log('[KuaiGe] 嗅探引擎已启动');

      // ========== 工具函数 ==========
      var reported = Object.create(null);       // 去重：已报告的 URL
      var reportedKeys = [];                     // 配合数组用于调试

      function extOf(url) {
        try {
          var s = String(url).split('?')[0].split('#')[0].toLowerCase();
          var m = s.match(/\.([a-z0-9]+)$/);
          return m ? m[1] : '';
        } catch(e) { return ''; }
      }

      // 明确非媒体的扩展名
      var NON_MEDIA_SET = {
        js:1,mjs:1,css:1,html:1,htm:1,json:1,php:1,asp:1,aspx:1,jsp:1,
        woff:1,woff2:1,ttf:1,otf:1,eot:1,png:1,jpeg:1,jpg:1,gif:1,svg:1,ico:1,webp:1,
        xml:1,wasm:1,map:1,txt:1,md:1,manifest:1
      };

      function isNonMediaExt(u) { return NON_MEDIA_SET[extOf(u)] === 1; }

      // 真媒体扩展名（正则必须在单行内，JS 不允许 /.../ 字面量含换行）
      var MEDIA_EXT_RE = /^(mp3|m4a|aac|wav|flac|ogg|opus|wma|ape|amr|aiff|au|ra|mp4|webm|mkv|avi|mov|ts|m3u8|m3u|f4m|mpd|ogv|x-m4a|x-flac|x-wav|x-aiff|x-ms-wma)$/;

      function isMediaExt(u) {
        var e = extOf(u);
        return e && !isNonMediaExt(u) && MEDIA_EXT_RE.test(e);
      }

      // 判断一个 URL 是否应该作为媒体上报
      function isLikelyMedia(url) {
        if (!url || typeof url !== 'string') return false;
        // blob 流总是上报
        if (url.indexOf('blob:') === 0) return true;
        // 有媒体扩展名
        if (isMediaExt(url)) return true;
        return false;
      }

      // 从扩展名推断类型
      function typeFromExt(url) {
        var e = extOf(url);
        if (!e) return 'other';
        if (/^(mp4|webm|mkv|avi|mov|ts|m3u8|m3u|f4m|mpd|ogv)$/.test(e)) return 'video';
        if (/^(mp3|m4a|aac|wav|flac|ogg|opus|wma|ape|amr|aiff|au|aif|x-m4a|x-flac|x-wav)$/.test(e)) return 'audio';
        return 'other';
      }

      // 从 Content-Type 推断类型
      function typeFromContentType(ct) {
        ct = (ct || '').toLowerCase().trim();
        if (!ct) return 'other';
        if (ct.indexOf('video/') === 0) return 'video';
        if (ct.indexOf('audio/') === 0) return 'audio';
        // HLS / DASH ���流协议
        if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('m3u8') !== -1 ||
            ct.indexOf('x-mpegurl') !== -1) return 'video';
        if (ct.indexOf('mpd+xml') !== -1 || ct.indexOf('dash') !== -1) return 'video';
        // 常见音频 MIME
        if (/x-m4a|ogg|webm|mp4|quicktime|flac|wav|aac|mp3|aiff|ms-wma/.test(ct)) return 'audio';
        // 二进制流（可能是媒体）
        if (ct.indexOf('octet-stream') !== -1) return 'other';
        return 'other';
      }

      // 判断 Content-Type 是否为媒体类型
      function isMediaContentType(ct) {
        return typeFromContentType(ct) !== 'other';
      }

      // ========== 安全的上报函数 ==========
      function report(url, source, referer, mediaType) {
        try {
          if (!url || typeof url !== 'string' || !url.trim()) return;
          if (reported[url]) return;          // 去重

          // 安全序列化：确保所有值都是基本类型
          var payload = {
            url: String(url).trim(),
            source: String(source || 'unknown'),
            referer: typeof referer === 'string' ? referer : (document.location ? document.location.href : ''),
            mediaType: String(mediaType || 'other')
          };

          // 二次校验：URL 必须是合法的 http(s)/blob
          if (payload.url.indexOf('http') !== 0 && payload.url.indexOf('blob:') !== 0) return;

          reported[url] = true;
          reportedKeys.push(url);

          window.webkit.messageHandlers.__HANDLER__.postMessage(payload);
        } catch(err) {
          // 静默失败，不影响页面正常功能
          console.warn('[KuaiGe] report error:', err.message || err);
        }
      }

      // 获取当前页面 referer
      function getRef() {
        try { return document.referrer || (document.location ? document.location.href : ''); }
        catch(e) { return ''; }
      }

      // ========== 1) HTMLMediaElement src 属性拦截 ==========
      try {
        var _srcDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (_srcDesc && _srcDesc.set) {
          var _origSrcSet = _srcDesc.set;
          Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            configurable: true,
            get: _srcDesc.get,
            set: function(v) {
              try {
                if (typeof v === 'string' && v.trim()) {
                  var tag = (this.tagName === 'VIDEO') ? 'video' : 'audio';
                  var extType = typeFromExt(v);
                  if (extType !== 'other') tag = extType;
                  if (isLikelyMedia(v)) {
                    report(v, 'media-src', getRef(), tag);
                  } else if (!isNonMediaExt(v)) {
                    // 无扩展名的直链（签名 URL 等），按元素类型上报
                    report(v, 'media-src', getRef(), tag);
                  }
                }
              } catch(e) {}
              return _origSrcSet.call(this, v);
            }
          });
        }
      } catch(e) {}

      // ========== 2) <source> / <audio> / <video> 的 setAttribute 拦截 ==========
      try {
        var _origSetAttr = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function(name, value) {
          try {
            var tn = this.tagName;
            if ((name === 'src' || name === 'srcset') &&
                (tn === 'SOURCE' || tn === 'AUDIO' || tn === 'VIDEO')) {
              var val = (name === 'srcset') ? String(value).split(/\s+/)[0] : String(value);
              if (val && val.trim()) {
                if (isLikelyMedia(val)) {
                  report(val, 'source-attr', getRef(), typeFromExt(val));
                } else if (!isNonMediaExt(val) && val.indexOf('data:') !== 0) {
                  report(val, 'source-attr', getRef(),
                         tn === 'VIDEO' ? 'video' : 'audio');
                }
              }
            }
          } catch(e) {}
          return _origSetAttr.call(this, name, value);
        };
      } catch(e) {}

      // ========== 3) fetch 拦截 ==========
      try {
        var _origFetch = window.fetch;
        window.fetch = function(input, init) {
          var reqUrl = '';
          if (input) {
            reqUrl = (typeof input === 'string') ? input : (input.url || '');
          }
          var ref = '';
          try {
            ref = (init && init.headers) ?
                   ((typeof init.headers.get === 'function') ? init.headers.get('Referer') : init.headers.Referer || '')
                   : '';
          } catch(e) {}

          // 请求 URL 本身像媒体 → 直接报
          if (isLikelyMedia(reqUrl)) {
            report(reqUrl, 'fetch-req', ref, typeFromExt(reqUrl));
          }

          return _origFetch.apply(this, arguments).then(function(resp) {
            try {
              if (resp && resp.headers && typeof resp.headers.get === 'function') {
                var ct = resp.headers.get('Content-Type') || '';
                var mt = typeFromContentType(ct);
                if (mt !== 'other' && reqUrl) {
                  report(reqUrl, 'fetch-resp', ref, mt);
                }
                // 检测 m3u8/HLS 响应体内容（克隆响应避免消费原始 body）
                if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('m3u8') !== -1 ||
                    ct.indexOf('text/plain') !== -1 || ct === '' || ct.indexOf('octet-stream') !== -1) {
                  resp.clone().text().then(function(text) {
                    detectM3U8Content(text, reqUrl);
                  }).catch(function(){});
                }
              }
            } catch(e) {}
            return resp;
          }).catch(function(err) {
            return Promise.reject(err);
          });
        };
      } catch(e) {}

      // ========== 4) XMLHttpRequest 拦截 ==========
      try {
        var _origXHROpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__kgUrl = url || '';
          return _origXHROpen.apply(this, arguments);
        };
        var _origXHRSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function() {
          var self = this;
          this.addEventListener('readystatechange', function() {
            try {
              if (self.readyState === 4) {
                var u = self.__kgUrl || '';
                var ct = '';
                try { ct = self.getResponseHeader ? (self.getResponseHeader('Content-Type') || '') : ''; } catch(e) {}
                var mt = typeFromContentType(ct);
                if (isLikelyMedia(u) || mt !== 'other') {
                  report(u, 'xhr-resp', getRef(), mt !== 'other' ? mt : typeFromExt(u));
                }
                // 检测 XHR 响应体是否为 m3u8/HLS 清单
                try {
                  var text = self.responseText;
                  if (text && typeof text === 'string') detectM3U8Content(text, u);
                } catch(e) {}
              }
            } catch(e) {}
          });
          return _origXHRSend.apply(this, arguments);
        };
      } catch(e) {}

      // ========== 5) Blob URL 创建拦截 ==========
      try {
        var _origCreateBlobURL = URL.createObjectURL;
        URL.createObjectURL = function(blob) {
          var url = _origCreateBlobURL.apply(this, arguments);
          try {
            var bt = (blob && blob.type) ? String(blob.type).toLowerCase() : '';
            if (bt.indexOf('audio') !== -1) report(url, 'blob-audio', getRef(), 'audio');
            else if (bt.indexOf('video') !== -1) report(url, 'blob-video', getRef(), 'video');
          } catch(e) {}
          return url;
        };
      } catch(e) {}

      // ========== 6) DOM 媒体元素扫描（含嵌套 source）==========
      function scanMediaElements() {
        try {
          var els = document.querySelectorAll('audio, video');
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var sources = [];

            // 元素自身的 src / currentSrc
            var s = el.src || el.currentSrc || '';
            if (s) sources.push(s);

            // 子 <source> 元素
            var kids = el.querySelectorAll('source');
            for (var j = 0; j < kids.length; j++) {
              var ss = kids[j].src || kids[j].getAttribute('src') || '';
              if (ss) sources.push(ss);
            }

            // poster 属性跳过（不是媒体文件）
            var tag = (el.tagName === 'VIDEO') ? 'video' : 'audio';

            for (var k = 0; k < sources.length; k++) {
              var url = sources[k];
              if (url && typeof url === 'string') {
                if (isLikelyMedia(url)) {
                  var et = typeFromExt(url);
                  report(url, 'dom-scan', getRef(), et !== 'other' ? et : tag);
                } else if (!isNonMediaExt(url) && url.indexOf('data:') !== 0 && url.indexOf('blob:') !== 0) {
                  report(url, 'dom-scan', getRef(), tag);
                }
              }
            }
          }
        } catch(e) {}
      }

      // ========== 7) Performance API 扫描（浏览器扩展核心兜底）==========
      // 这是很多动态加载/加密 URL 的唯一抓取途径
      function scanPerformanceEntries() {
        try {
          if (typeof performance === 'undefined' ||
              typeof performance.getEntriesByType !== 'function') return;

          var entries = performance.getEntriesByType('resource');
          for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            var url = e.name;
            if (!url) continue;

            // 快速预筛：只检查可能像媒体的 URL
            if (!isLikelyMedia(url)) {
              // 再检查是否有媒体相关的 Content-Type hint
              // （PerformanceEntry 的 initiatorType 可能是 'media' 或其他）
              continue;
            }

            // 用响应的 Content-Type（如果可用）来确认
            // 注意：Performance API 在某些 iOS WKWebView 中可能不暴露完整的 response header
            // 所以主要依赖 URL 特征
            var ct = '';
            try {
              // performance.resourceTimingBufferEnabled 可能限制访问
              if (e.nextHopProtocol) {} // 测试属性是否存在
            } catch(x) {}

            var t = typeFromExt(url);
            report(url, 'performance-api', getRef(), t !== 'other' ? t : 'other');
          }
        } catch(e) {}
      }

      // ========== 8) m3u8/HLS 内容检测 ==========
      // 很多视频网站用 XHR/fetch 加载 .m3u8 清单，内含真正的 ts 分片 URL
      function detectM3U8Content(text, baseSourceUrl) {
        try {
          if (!text || typeof text !== 'string') return;
          // m3u8 文件特征
          if (text.indexOf('#EXTM3U') === -1 && text.indexOf('#EXTINF') === -1) return;

          // 提取其中的 ts/分片 URL
          var lines = text.split('\n');
          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line || line.indexOf('#') === 0) continue;
            // 绝对或相对 URL
            if (line.indexOf('http') === 0 || line.indexOf('/') === 0) {
              var absUrl = line;
              if (line.indexOf('http') !== 0 && baseSourceUrl) {
                // 解析相对 URL
                try {
                  absUrl = new URL(line, baseSourceUrl).href;
                } catch(x) { absUrl = line; }
              }
              report(absUrl, 'hls-segment', getRef(), 'video');
            }
          }
          // 上报 m3u8 本身作为视频源
          if (baseSourceUrl) {
            report(baseSourceUrl, 'hls-manifest', getRef(), 'video');
          }
        } catch(e) {}
      }

      // ========== 9) MediaSource API 拦截（高级流媒体）==========
      try {
        var _origAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function(mime) {
          // 当网站用 MSE (Media Source Extensions) 动态注入音视频流时触发
          try {
            console.log('[KuaiGe] MediaSource.addSourceBuffer:', mime);
          } catch(e) {}
          return _origAddSourceBuffer.apply(this, arguments);
        };
      } catch(e) {}

      // ========== 启动扫描 ==========
      // 立即执行一次 DOM 扫描
      scanMediaElements();

      // 周期性扫描（捕获 SPA 动态加载的内容）
      setInterval(scanMediaElements, 2000);

      // Performance API 定期扫描（每 3 秒）
      setInterval(scanPerformanceEntries, 3000);

      // 初始延迟后首次 Performance 扫描（等页面资源加载一会）
      setTimeout(scanPerformanceEntries, 1500);
      setTimeout(scanPerformanceEntries, 4000);

      // MutationObserver 监听 DOM 变化
      try {
        var _observer = new MutationObserver(function(mutations) {
          scanMediaElements();
          // 每 10 次 mutation 触发一次 Performance 扫描
          if (Math.random() < 0.1) scanPerformanceEntries();
        });
        _observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'data-src', 'data-url', 'data-source']
        });
      } catch(e) {}

    })();
    """#

    /// 把脚本里的占位符替换成真实的 handler 名称
    static func build() -> String {
        source.replacingOccurrences(of: "__HANDLER__", with: handlerName)
    }
}
