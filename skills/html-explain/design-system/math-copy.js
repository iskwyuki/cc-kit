(function () {
  function fallbackCopy(tex) {
    var ta = document.createElement('textarea');
    ta.value = tex;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }

  function copyText(tex) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(tex).catch(function () {
        fallbackCopy(tex);
      });
    }
    fallbackCopy(tex);
    return Promise.resolve();
  }

  function makeButton(tex) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'mb-math-copy';
    btn.setAttribute('aria-label', '数式の LaTeX をコピー');
    btn.textContent = 'copy';
    btn.addEventListener('click', function () {
      copyText(tex).then(function () {
        btn.textContent = 'copied';
        setTimeout(function () {
          btn.textContent = 'copy';
        }, 1200);
      });
    });
    return btn;
  }

  function attachCopyUi(item) {
    var root = item.typesetRoot;
    if (!root || !root.parentNode) return;
    var wrap = document.createElement(item.display ? 'div' : 'span');
    wrap.className = item.display ? 'mb-math-block' : 'mb-math-inline';
    root.parentNode.insertBefore(wrap, root);
    wrap.appendChild(root);
    wrap.appendChild(makeButton(item.math));
  }

  window.MathJax = {
    // Artifact の CSP は外部ホストへの通信を遮断する。同梱しているのは
    // tex-svg-full（TeX の全パッケージ + SVG 出力）なので、標準的なコマンドは
    // \boldsymbol も含めてバンドル内で解決できる。
    // 残る遅延読み込みの入口だけを塞ぐ:
    //   - require: \require{...} が任意のパッケージを実行時に取りに行く
    //   - enableMenu: 右クリックメニューが a11y 拡張（speech-rule-engine）を
    //     取りに行く。数式の LaTeX コピーは下の mb-math-copy ボタンが担うので、
    //     メニューを無効にしても失われる機能はない
    options: { enableMenu: false },
    tex: {
      packages: { '[-]': ['require'] },
      inlineMath: [['$', '$']],
      displayMath: [['$$', '$$']]
    },
    startup: {
      pageReady: function () {
        return MathJax.startup.defaultPageReady().then(function () {
          for (var item of MathJax.startup.document.math) {
            attachCopyUi(item);
          }
        });
      }
    }
  };
})();
