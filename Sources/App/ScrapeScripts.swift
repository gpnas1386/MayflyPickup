import Foundation

/// 注入到网页里的采集脚本（在 WKWebView 中运行）
enum ScrapeScripts {

    /// 全局桥 + 抓包钩子，documentStart 注入
    static let bootstrap = #"""
    (function(){
      if (window.__mayflyInstalled) return; window.__mayflyInstalled = true;
      window.__mayflyPost = function(s){ try { window.webkit.messageHandlers.mayfly.postMessage(String(s)); } catch(e) {} };
      window.__cap = [];
      function push(u, b){
        try {
          if (!b) return;
          if (typeof b !== 'string') b = JSON.stringify(b);
          if (b.length > 300000) b = b.slice(0, 300000);
          if (b.indexOf('"') < 0) return;
          window.__cap.push({u: String(u||'').slice(0,300), b: b});
          if (window.__cap.length > 40) window.__cap.shift();
        } catch(e){}
      }
      var of = window.fetch;
      if (of) {
        window.fetch = function(){
          var url = arguments[0];
          try { url = (typeof url === 'string') ? url : (url && url.url) || ''; } catch(e){}
          return of.apply(this, arguments).then(function(r){
            try { r.clone().text().then(function(t){ push(url, t); }); } catch(e){}
            return r;
          });
        };
      }
      var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u){ this.__u = u; return oo.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(){
        var x = this;
        x.addEventListener('load', function(){
          try {
            var t = x.responseText;
            if (!t && x.response && typeof x.response === 'object') t = JSON.stringify(x.response);
            push(x.__u, t);
          } catch(e){}
        });
        return os.apply(this, arguments);
      };
    })();
    """#

    /// 淘宝：身份码（mtop.cainiao.pickup.identity）
    static let tbIdentity = #"""
    (function(){
      try {
        if (!(window.lib && window.lib.mtop)) { window.__mayflyPost(JSON.stringify({t:'identity', err:'NOLIB'})); return; }
        var lib = window.lib.mtop;
        var apis = [
          ['mtop.cainiao.pickup.identity.getIdentityMessage', {}],
          ['mtop.cainiao.pickup.identity.getIdentityCode', {}],
          ['mtop.cainiao.pickup.identity.query', {}]
        ];
        var out = {t:'identity', rows:[]};
        function next(i){
          if (i >= apis.length) { window.__mayflyPost(JSON.stringify(out)); return; }
          lib.request({api: apis[i][0], v:'1.0', data: apis[i][1], ecode:1, dataType:'json', type:'GET', timeout:9000})
            .then(function(r){
              out.rows.push({api: apis[i][0], ok: true, ret: (r && r.ret || []).join('|'), data: (r && r.data) || r});
            }, function(e){
              out.rows.push({api: apis[i][0], ok: false, ret: ((e && e.ret) || []).join('|')});
            }).then(function(){ next(i+1); });
        }
        next(0);
      } catch(e) { window.__mayflyPost(JSON.stringify({t:'identity', err:String(e)})); }
    })();
    """#

    /// 淘宝：按手机号 / 运单号批量查代收包裹（mtop.cainiao.pickup.search.*）
    static func tbPackages(waybills: [String], phone: String) -> String {
        let wbJSON = (try? JSONSerialization.data(withJSONObject: waybills)) ?? Data("[]".utf8)
        let wbStr = String(data: wbJSON, encoding: .utf8) ?? "[]"
        let phoneStr = phone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return """
        (function(){
          try {
            if (!(window.lib && window.lib.mtop)) { window.__mayflyPost(JSON.stringify({t:'packages', err:'NOLIB'})); return; }
            var lib = window.lib.mtop;
            var rows = [];
            function call(tag, api, data, ver){
              return lib.request({api:api, v:ver||'1.0', data:data, ecode:1, dataType:'json', type:'GET', timeout:9000})
                .then(function(r){ rows.push({tag:tag, api:api, ok:true, ret:(r&&r.ret||[]).join('|'), body:(r&&r.data)||r}); },
                      function(e){ rows.push({tag:tag, api:api, ok:false, ret:((e&&e.ret)||[]).join('|')}); });
            }
            var wbs = \(wbStr);
            var phone = "\(phoneStr)";
            var jobs = [];
            if (phone) {
              ['1.0','2.0'].forEach(function(v){
                jobs.push(call('phone01@'+v, 'mtop.cainiao.pickup.search.queryMultiStationPackages', {searchTypes:'["01"]', searchValue: phone}, v));
                jobs.push(call('phone01b@'+v, 'mtop.cainiao.pickup.plus.querymultistapackages4xy', {searchTypes:'["01"]', searchValue: phone}, v));
              });
            }
            wbs.slice(0, 6).forEach(function(w, i){
              ['1.0','2.0'].forEach(function(v){
                jobs.push(call('wb'+i+'@'+v, 'mtop.cainiao.pickup.search.queryMultiStationPackages', {searchTypes:'["03"]', searchValue: String(w)}, v));
              });
            });
            Promise.all(jobs).then(function(){
              window.__mayflyPost(JSON.stringify({t:'packages', rows: rows}));
            });
          } catch(e){ window.__mayflyPost(JSON.stringify({t:'packages', err:String(e)})); }
        })();
        """
    }

    /// 读取页面文本 + 抓包缓存 + 注入诊断
    static let dumpPage = #"""
    (function(){
      var t = '';
      try { t = (document.body && document.body.innerText) || ''; } catch(e){}
      var cap = []; try { cap = window.__cap || []; } catch(e){}
      var urls = [];
      try { for (var i = 0; i < cap.length && i < 8; i++) urls.push(String(cap[i].u || '').slice(0, 120)); } catch(e){}
      var dbg = {
        inst: !!window.__mayflyInstalled,
        capN: cap.length,
        capUrls: urls,
        title: String(document.title || '').slice(0, 60),
        url: String(location.href).slice(0, 200)
      };
      var out = {t:'page', url: location.href, text: t.slice(0, 60000), cap: cap, dbg: dbg};
      window.__mayflyPost(JSON.stringify(out));
      return 'ok';
    })();
    """#

    /// 页面登录态粗探针
    static let loginProbe = #"""
    (function(){
      var t = '';
      try { t = (document.body && document.body.innerText) || ''; } catch(e){}
      var out = {t:'probe', url: location.href, text: t.slice(0, 4000)};
      window.__mayflyPost(JSON.stringify(out));
      return 'ok';
    })();
    """#
}
