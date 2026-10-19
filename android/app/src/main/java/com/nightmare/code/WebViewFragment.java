package com.nightmare.code;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.database.ContentObserver;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.provider.Settings;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;

public class WebViewFragment extends Fragment {

    OrientationListener myOrientoinListener;

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container, @Nullable Bundle savedInstanceState) {
        WebView mWebView;
        myOrientoinListener = new OrientationListener(getActivity());
        checkState();
        getContext().getContentResolver().registerContentObserver(
                Settings.System.getUriFor(Settings.System.ACCELEROMETER_ROTATION),
                true,
                new ContentObserver(new Handler()) {
                    @Override
                    public void onChange(boolean selfChange) {
                        checkState();
                    }
                }
        );
        mWebView = new WebView(getContext());
        // Replace WebView's long-press context menu with the editor toolbar injected below.
        mWebView.setOnLongClickListener(v -> true);
        ViewGroup.LayoutParams layoutParams = new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        );
        mWebView.setLayoutParams(layoutParams);

        WebSettings mWebSettings = mWebView.getSettings();
        mWebSettings.setJavaScriptEnabled(true);
        mWebSettings.setJavaScriptCanOpenWindowsAutomatically(true);
        mWebSettings.setUseWideViewPort(true);
        mWebSettings.setAllowFileAccess(true);
        mWebSettings.setDomStorageEnabled(true);
        mWebSettings.setDatabaseEnabled(true);
        mWebSettings.setLoadWithOverviewMode(true);
        mWebSettings.setDefaultTextEncodingName("utf-8");
        mWebSettings.setLoadsImagesAutomatically(true);
        mWebSettings.setSupportMultipleWindows(true);
        mWebView.addJavascriptInterface(new JavaScriptBridge(getContext()), "Android");
        mWebView.setWebChromeClient(webChromeClient);

        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);

                String jsCode = "(() => { " +
                        "const clip = navigator.clipboard || {}; " +
                        "const readNative = () => Promise.resolve(Android.getClipboardData()); " +
                        "const writeNative = text => { Android.setClipboardData(String(text)); return Promise.resolve(); }; " +
                        "try { if (!navigator.clipboard) Object.defineProperty(navigator, 'clipboard', { configurable: true, value: clip }); } " +
                        "catch (e) { console.log('Code LFA clipboard object:', e); } " +
                        "try { Object.defineProperty(clip, 'readText', { configurable: true, writable: true, value: readNative }); } " +
                        "catch (e) { try { clip.readText = readNative; } catch (_) {} } " +
                        "try { Object.defineProperty(clip, 'writeText', { configurable: true, writable: true, value: writeNative }); } " +
                        "catch (e) { try { clip.writeText = writeNative; } catch (_) {} } " +
                        "})();";
                view.evaluateJavascript(jsCode, null);

                // Editor touch fix and working long-press toolbar. Monaco still receives
                // pointer movement, so drag selection/caret gestures are not cancelled.
                String touchFixJs = """
                (() => {
                  if (window.__codeLFATouchToolsInstalled) return;
                  window.__codeLFATouchToolsInstalled = true;

                  const threshold = 12;
                  const longPressDelay = 520;
                  const toolbarId = '__codeLFASelectionToolbar';
                  let gesture = null;
                  let lastToolbarContext = null;
                  let toolbar = null;

                  function getEditor(target) {
                    const element = target instanceof Element ? target : null;
                    return element ? element.closest('.monaco-editor') : null;
                  }

                  function getInput(editor) {
                    return editor ? editor.querySelector('textarea.inputarea') : null;
                  }

                  function keyboardVisible() {
                    const viewport = window.visualViewport;
                    if (!viewport) return false;
                    return window.innerHeight - viewport.height > 120;
                  }

                  function removeToolbar() {
                    if (toolbar && toolbar.isConnected) toolbar.remove();
                    toolbar = null;
                  }

                  function dispatchShortcut(input, key) {
                    if (!input) return;
                    const code = 'Key' + key.toUpperCase();
                    const init = {
                      key: key,
                      code: code,
                      keyCode: key.toUpperCase().charCodeAt(0),
                      which: key.toUpperCase().charCodeAt(0),
                      ctrlKey: true,
                      bubbles: true,
                      cancelable: true,
                      composed: true
                    };
                    try {
                      input.dispatchEvent(new KeyboardEvent('keydown', init));
                      input.dispatchEvent(new KeyboardEvent('keyup', init));
                    } catch (e) {
                      console.log('Code LFA editor shortcut failed:', e);
                    }
                  }

                  function runAction(action) {
                    const context = lastToolbarContext;
                    if (!context || !context.input || !context.input.isConnected) {
                      removeToolbar();
                      return;
                    }

                    const input = context.input;
                    // The built-in Monaco/VS Code keybinding handler performs the edit.
                    // Clipboard reads/writes are bridged to Android's real clipboard above.
                    const keys = { selectAll: 'a', paste: 'v', copy: 'c', cut: 'x' };
                    dispatchShortcut(input, keys[action]);
                    removeToolbar();
                  }

                  function showToolbar(x, y, editor, input) {
                    if (!editor || !input) return;
                    lastToolbarContext = { editor: editor, input: input };
                    removeToolbar();

                    const menu = document.createElement('div');
                    toolbar = menu;
                    menu.id = toolbarId;
                    menu.setAttribute('role', 'toolbar');
                    menu.setAttribute('aria-label', 'Acciones de texto');
                    menu.style.cssText = [
                      'position:fixed',
                      'z-index:2147483647',
                      'display:flex',
                      'align-items:center',
                      'gap:3px',
                      'padding:5px',
                      'background:#292929',
                      'color:#ffffff',
                      'border:1px solid #666666',
                      'border-radius:9px',
                      'box-shadow:0 4px 18px rgba(0,0,0,.45)',
                      'font:14px Roboto,Arial,sans-serif',
                      'white-space:nowrap',
                      'max-width:calc(100vw - 12px)',
                      'overflow-x:auto',
                      'touch-action:manipulation',
                      'user-select:none',
                      '-webkit-user-select:none'
                    ].join(';');

                    const actions = [
                      ['Seleccionar todo', 'selectAll'],
                      ['Pegar', 'paste'],
                      ['Copiar', 'copy'],
                      ['Cortar', 'cut']
                    ];

                    for (const item of actions) {
                      const button = document.createElement('button');
                      button.type = 'button';
                      button.textContent = item[0];
                      button.style.cssText = [
                        'border:0',
                        'border-radius:6px',
                        'padding:9px 10px',
                        'background:transparent',
                        'color:#ffffff',
                        'font:inherit',
                        'min-height:36px',
                        'touch-action:manipulation',
                        'white-space:nowrap'
                      ].join(';');
                      button.addEventListener('pointerdown', event => {
                        event.stopPropagation();
                      });
                      button.addEventListener('click', event => {
                        event.preventDefault();
                        event.stopPropagation();
                        runAction(item[1]);
                      });
                      button.addEventListener('pointerenter', () => {
                        button.style.background = '#454545';
                      });
                      button.addEventListener('pointerleave', () => {
                        button.style.background = 'transparent';
                      });
                      menu.appendChild(button);
                    }

                    document.body.appendChild(menu);
                    const width = menu.getBoundingClientRect().width;
                    const height = menu.getBoundingClientRect().height;
                    const left = Math.max(6, Math.min(x - width / 2, window.innerWidth - width - 6));
                    const top = y - height - 14 >= 6 ? y - height - 14 : Math.min(y + 18, window.innerHeight - height - 6);
                    menu.style.left = left + 'px';
                    menu.style.top = Math.max(6, top) + 'px';
                  }

                  function selectWordAtPoint(x, y, editor) {
                    // Monaco handles this event in its normal editor event path. We do not
                    // interfere with pointer events or manually alter the editor's model.
                    const target = document.elementFromPoint(x, y);
                    if (!target || !editor.contains(target)) return;
                    try {
                      target.dispatchEvent(new MouseEvent('dblclick', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        detail: 2,
                        clientX: x,
                        clientY: y,
                        button: 0
                      }));
                    } catch (_) {}
                  }

                  document.addEventListener('pointerdown', event => {
                    if (event.pointerType !== 'touch' || !event.isPrimary) return;
                    if (event.target && event.target.closest && event.target.closest('#' + toolbarId)) return;

                    const editor = getEditor(event.target);
                    if (!editor) return;
                    const input = getInput(editor);
                    if (!input) return;

                    const state = {
                      pointerId: event.pointerId,
                      editor: editor,
                      input: input,
                      startX: event.clientX,
                      startY: event.clientY,
                      moved: false,
                      longPressed: false,
                      wasReadOnly: input.readOnly,
                      wasKeyboardVisible: keyboardVisible(),
                      timer: null
                    };
                    gesture = state;

                    // Prevent focus-on-scroll from opening the soft keyboard. Movement is
                    // still delivered to Monaco so its selection and drag handling can run.
                    if (!state.wasKeyboardVisible) input.readOnly = true;

                    state.timer = setTimeout(() => {
                      if (gesture !== state || state.moved) return;
                      state.longPressed = true;
                      selectWordAtPoint(state.startX, state.startY, state.editor);
                      showToolbar(state.startX, state.startY, state.editor, state.input);
                    }, longPressDelay);
                  }, true);

                  document.addEventListener('pointermove', event => {
                    if (!gesture || event.pointerId !== gesture.pointerId) return;
                    const dx = event.clientX - gesture.startX;
                    const dy = event.clientY - gesture.startY;
                    if (Math.hypot(dx, dy) > threshold) {
                      gesture.moved = true;
                      if (gesture.timer) clearTimeout(gesture.timer);
                      gesture.timer = null;
                    }
                  }, true);

                  document.addEventListener('contextmenu', event => {
                    const editor = getEditor(event.target);
                    if (!editor) return;
                    event.preventDefault();
                    event.stopPropagation();
                    if (event.stopImmediatePropagation) event.stopImmediatePropagation();
                    if (gesture) {
                      gesture.longPressed = true;
                      if (gesture.timer) clearTimeout(gesture.timer);
                      gesture.timer = null;
                    }
                    const input = getInput(editor);
                    showToolbar(event.clientX, event.clientY, editor, input);
                  }, true);

                  function finishGesture(event, cancelled) {
                    if (!gesture) return;
                    if (event && event.pointerId !== gesture.pointerId) return;
                    const state = gesture;
                    gesture = null;
                    if (state.timer) clearTimeout(state.timer);
                    if (cancelled) state.moved = true;
                    state.input.readOnly = state.wasReadOnly;

                    if (state.moved) {
                      // A scroll/drag must not leave focus on the hidden input and summon IME.
                      setTimeout(() => {
                        if (!state.wasKeyboardVisible && document.activeElement === state.input) {
                          state.input.blur();
                        }
                      }, 60);
                    } else if (!state.longPressed) {
                      // A tap behaves like a normal editor tap: keep the cursor and enable typing.
                      try {
                        state.input.focus({ preventScroll: true });
                      } catch (_) {
                        state.input.focus();
                      }
                    }
                  }

                  document.addEventListener('pointerup', event => finishGesture(event, false), true);
                  document.addEventListener('pointercancel', event => finishGesture(event, true), true);

                  document.addEventListener('pointerdown', event => {
                    if (toolbar && !toolbar.contains(event.target)) removeToolbar();
                  }, false);
                  window.addEventListener('resize', removeToolbar);
                  window.addEventListener('scroll', removeToolbar, true);
                })();
                """;
                view.evaluateJavascript(touchFixJs, null);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                view.loadUrl(url);
                return true;
            }
        });
        mWebView.loadUrl("http://127.0.0.1:20000");
        return mWebView;
    }

    public static class JavaScriptBridge {
        Context mContext;

        JavaScriptBridge(Context c) {
            mContext = c;
        }

        @JavascriptInterface
        public String getClipboardData() {
            ClipboardManager clipboard = (ClipboardManager) mContext.getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null) return "";
            ClipData clip = clipboard.getPrimaryClip();
            if (clip != null && clip.getItemCount() > 0) {
                CharSequence text = clip.getItemAt(0).coerceToText(mContext);
                return text == null ? "" : text.toString();
            }
            return "";
        }

        @JavascriptInterface
        public boolean setClipboardData(String text) {
            if (mContext == null) return false;
            final String value = text == null ? "" : text;
            Handler mainHandler = new Handler(android.os.Looper.getMainLooper());
            mainHandler.post(() -> {
                ClipboardManager clipboard = (ClipboardManager) mContext.getSystemService(Context.CLIPBOARD_SERVICE);
                if (clipboard != null) {
                    clipboard.setPrimaryClip(ClipData.newPlainText("Code LFA", value));
                }
            });
            return true;
        }
    }

    void checkState() {
        boolean autoRotateOn = (android.provider.Settings.System.getInt(
                getContext().getContentResolver(),
                Settings.System.ACCELEROMETER_ROTATION,
                0
        ) == 1);
        if (autoRotateOn) {
            myOrientoinListener.enable();
        } else {
            myOrientoinListener.disable();
        }
    }

    WebChromeClient webChromeClient = new WebChromeClient() {
        @Override
        public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
            WebView childView = new WebView(getContext());
            childView.setBackgroundColor(Color.GREEN);
            childView.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, String url) {
                    getContext().startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                    return true;
                }
            });
            WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
            transport.setWebView(childView);
            resultMsg.sendToTarget();
            return true;
        }
    };

    @Override
    public void onStop() {
        super.onStop();
        myOrientoinListener.disable();
    }
}
