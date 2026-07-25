import Foundation

/// 注入到 WKWebView 的嗅探脚本（通用：拦截任意平台的音频/视频资源）
enum SniffScript {
    /// 与 WKUserContentController.add(_:name:) 中的 name 保持一致
    static let handlerName = "sniff"

    /// 通用音频/视频 URL 匹配（覆盖主流平台 CDN + 常见格式）
    static let source: String = #"""
    (function () {
      if (window.__kgSniffInstalled) return;
      window.__kgSniffInstalled = true;

      // ========== 去重（同一 URL 只报告一次）==========
      var reported = {};

      function isAudioUrl(u) {
        if (!u || typeof u !== 'string') return false;
        try {
          var s = u.toLowerCase();
          // 1) 音频扩展名
          if (/\.(mp3|m4a|aac|wav|flac|ogg|opus|wma|ape|amr)(\?|#|$)/.test(s)) return true;
          // 2) 视频扩展名（很多平台用 video 标签播音频）
          if (/\.(mp4|webm|mkv|avi|mov|ts)(\?|#|$)/.test(s)) return true;
          // 3) 流媒体 manifest
          if (/\.(m3u8|m3u|f4m)(\?|#|$)/.test(s)) return true;
          // 4) 主流平台 CDN / OSS 域名
          var cdnPatterns = [
            // 腾讯系
            'myqcloud.com', '.cos.', 'cdn-go.cn', 'cncdnzbj.com',
            'dl.stream.qqmusic.qq.com', 'isure.stream.qqmusic.qq.com',
            'y.qq.com', 'qqmusic.qq.com',
            // 网易云
            'music.163.com', 'm10.music.126.net', 'm7.music.126.net',
            'p1.music.126.net', 'p2.music.126.net',
            // 酷狗
            'kugou.com', 'imge.kugou.com', 'cdn.kugou.com',
            'fs.kugou.com', 'mr.kugou.com',
            // 酷我
            'kuwo.cn', 'kuwoyy.com', 'other.web.rh01.sycdn.kuwo.cn',
            'other.web.nm01.sycdn.kuwo.cn',
            // 咪咕
            'migu.cn', 'dsmusic.migu.cn',
            // B站
            'bilivideo.com', 'hdslb.com', 'acgvideo.com', 'bilibili.com',
            // 抖音 / 快歌 / 短视频
            'kuaigeai.cn', 'douyin.com', 'douyinpic.com', 'bytecdntp.com',
            'bytedancecdn.com', 'toutiao.com', 'snssdk.com',
            // 阿里云 OSS
            'aliyuncs.com', '.oss-', 'oss-cn-',
            // 七牛
            'qiniucdn.com', 'qbox.me', 'qnssl.com', 'cdn-qiniu.',
            // 又拍云
            'upaiyun.com', 'upcdn.com',
            // 华为云 OBS
            'obs.myhuaweicloud.com',
            // AWS S3 / CloudFront
            'amazonaws.com', 'cloudfront.net',
            // 其他常见 CDN
            'cdn-cos.', 'cdn.jsdelivr.net', 'unpkg.com', 'cdnjs.'
          ];
          for (var i = 0; i < cdnPatterns.length; i++) {
            if (s.indexOf(cdnPatterns[i]) !== -1) return true;
          }
          // 5) blob URL（可能是音视频）
          if (s.indexOf('blob:') === 0) return true;
          return false;
        } catch (e) { return false; }
      }

      function report(url, source, referer) {
        try {
          if (!url || reported[url]) return;
          reported[url] = true;
          window.webkit.messageHandlers.__HANDLER__.postMessage({
            url: url,
            source: source,
            referer: referer || (document.location ? document.location.href : '')
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
              try { if (isAudioUrl(v)) report(v, 'media-src', document.referrer); } catch (e) {}
              return origSrcSet.call(this, v);
            }
          });
        }
      } catch (e) {}

      // 拦截 <source> 标签的 src 属性变化
      try {
        var origSetAttr = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          try {
            if ((name === 'src' || name === 'srcset') &&
                (this.tagName === 'SOURCE' || this.tagName === 'AUDIO' || this.tagName === 'VIDEO' ||
                 this.tagName === 'TRACK')) {
              if (isAudioUrl(value)) report(value, 'source-attr', document.referrer);
            }
          } catch (e) {}
          return origSetAttr.call(this, name, value);
        };
      } catch (e) {}

      // ========== 2) 拦截 fetch ==========
      try {
        var origFetch = window.fetch;
        window.fetch = function (input, init) {
          var url = (input && input.url) ? input.url
                   : (typeof input === 'string' ? input : '');
          var ref = '';
          try { ref = (init && init.headers && init.headers.get)
                    ? init.headers.get('Referer')
                    : (document.referrer || ''); } catch(e) {}
          if (isAudioUrl(url)) report(url, 'fetch', ref);
          return origFetch.apply(this, arguments).then(function (resp) {
            try {
              var ct = (resp && resp.headers && resp.headers.get)
                       ? resp.headers.get('Content-Type') : '';
              if (ct && /audio|mpegurl|octet-stream|mp4|quicktime|video\/mp4/.test(ct.toLowerCase())) {
                report(url, 'fetch-resp', ref);
              }
            } catch (e) {}
            return resp;
          });
        };
      } catch (e) {}

      // ========== 3) 拦截 XMLHttpRequest ==========
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
                if (isAudioUrl(self.__kgUrl) || /audio|mpegurl|octet-stream|mp4|quicktime|video\/mp4/.test(ct.toLowerCase())) {
                  report(self.__kgUrl, 'xhr', document.referrer);
                }
              }
            } catch (e) {}
          });
          return origSend.call(this);
        };
      } catch (e) {}

      // ========== 4) 拦截 blob URL 创建（很多平台用 blob 播放）==========
      try {
        var origCreateURL = URL.createObjectURL;
        URL.createObjectURL = function (blob) {
          var url = origCreateURL.apply(this, arguments);
          try {
            if (blob && (blob.type || '').indexOf('audio') !== -1) {
              report(url, 'blob-audio', document.referrer);
            }
            if (blob && (blob.type || '').indexOf('video') !== -1) {
              report(url, 'blob-video', document.referrer);
            }
          } catch (e) {}
          return url;
        };
      } catch (e) {}

      // ========== 5) 拦截 MediaSource / HLS ==========
      try {
        var origAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function (mime) {
          // 记录这个 MediaSource 正在被使用，后续通过周期扫描关联 URL
          this.__kgMime = mime;
          return origAddSourceBuffer.apply(this, arguments);
        };
      } catch (e) {}

      // ========== 6) 周期扫描已有媒体元素（含动态插入的）==========
      function scan() {
        try {
          var els = document.querySelectorAll('audio, video, source');
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var s = el.src || el.currentSrc || el.getAttribute('src');
            if (s && isAudioUrl(s)) report(s, 'media-element-scan', document.referrer);

            // 也检查 <source> 子元素
            if (el.querySelector) {
              var sources = el.querySelectorAll('source');
              for (var j = 0; j < sources.length; j++) {
                var ss = sources[j].src || sources[j].getAttribute('src');
                if (ss && isAudioUrl(ss)) report(ss, 'nested-source', document.referrer);
              }
            }
          }
        } catch (e) {}
      }
      scan();
      setInterval(scan, 1500);

      // ========== 7) 监听 DOM 变化（SPA 动态加载内容）==========
      try {
        var observer = new MutationObserver(function () {
          scan();
        });
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
