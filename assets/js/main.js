/* ═══════════════════════════════════════════
   ЛаСТОчка11 — интерактив
   ═══════════════════════════════════════════ */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ─────────── Прелоадер ─────────── */
  (function preloader() {
    var root  = document.getElementById('preloader');
    var count = document.getElementById('preloaderCount');
    var bar   = document.getElementById('preloaderBar');
    var hero  = document.getElementById('hero');
    if (!root) return;

    function finish() {
      root.classList.add('is-done');
      if (hero) hero.classList.add('is-in');
      setTimeout(function () { root.remove(); }, 900);
    }

    if (reduced) { finish(); return; }

    var n = 0;
    var timer = setInterval(function () {
      n = Math.min(100, n + Math.random() * 11 + 4);
      var v = Math.round(n);
      count.textContent = v;
      bar.style.width = v + '%';
      if (v >= 100) {
        clearInterval(timer);
        setTimeout(finish, 380);
      }
    }, 90);
  })();


  /* ─────────── Проявление блоков по скроллу ─────────── */
  (function reveal() {
    var items = document.querySelectorAll('.reveal');
    if (!items.length) return;

    if (reduced || !('IntersectionObserver' in window)) {
      items.forEach(function (el) { el.classList.add('is-in'); });
      return;
    }

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add('is-in');
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

    items.forEach(function (el) { io.observe(el); });
  })();



  /* ─────────── Параллакс фона героя ─────────── */
  (function parallax() {
    var img  = document.getElementById('heroImg');
    var hero = document.getElementById('hero');
    if (!img || !hero || reduced) return;

    var ticking = false;
    function frame() {
      var y = window.scrollY;
      if (y < window.innerHeight * 1.2) {
        img.style.transform = 'translate3d(0,' + (y * 0.22) + 'px,0) scale(1.04)';
      }
      ticking = false;
    }
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(frame); }
    }, { passive: true });
  })();


  /* ─────────── Шапка: прячется при скролле вниз ─────────── */
  (function topbar() {
    var bar = document.getElementById('topbar');
    if (!bar) return;

    var last = 0;
    window.addEventListener('scroll', function () {
      var y = window.scrollY;
      var down = y > last && y > 220;
      bar.classList.toggle('is-hidden', down && !document.body.classList.contains('is-locked'));
      last = y;
    }, { passive: true });
  })();


  /* ─────────── Мобильное меню ─────────── */
  (function drawer() {
    var btn  = document.getElementById('burger');
    var menu = document.getElementById('drawer');
    if (!btn || !menu) return;

    function toggle(open) {
      btn.classList.toggle('is-open', open);
      menu.classList.toggle('is-open', open);
      document.body.classList.toggle('is-locked', open);
      btn.setAttribute('aria-expanded', String(open));
    }

    btn.addEventListener('click', function () {
      toggle(!menu.classList.contains('is-open'));
    });
    menu.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function () { toggle(false); });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') toggle(false);
    });
  })();


  /* ─────────── «Открыто / закрыто» на главном экране ─────────── */
  (function openStatus() {
    var el = document.getElementById('heroStatus');
    if (!el) return;

    /* График сервиса. Ключ — день недели, 0 — воскресенье, null — выходной.
       TODO: привести к реальному графику; тот же график продублирован
       в разметке организации в <head> и в секции «Контакты». */
    var HOURS = {
      1: [9, 19], 2: [9, 19], 3: [9, 19], 4: [9, 19], 5: [9, 19],
      6: [10, 16],
      0: null
    };
    var DAYS = ['воскресенье', 'понедельник', 'вторник', 'среду', 'четверг', 'пятницу', 'субботу'];

    /* Считаем по времени Сыктывкара (МСК), а не по часам посетителя —
       иначе гость из другого пояса увидит неверный статус. */
    function mskNow() {
      var n = new Date();
      return new Date(n.getTime() + n.getTimezoneOffset() * 60000 + 3 * 3600000);
    }
    function hhmm(h) { return (h < 10 ? '0' : '') + h + ':00'; }

    function nextWorkday(from) {
      for (var i = 1; i <= 7; i++) {
        var d = (from + i) % 7;
        if (HOURS[d]) return { day: d, hour: HOURS[d][0], shift: i };
      }
      return null;
    }

    function render() {
      var t = mskNow();
      var day = t.getDay();
      var mins = t.getHours() * 60 + t.getMinutes();
      var today = HOURS[day];
      var isOpen = false;
      var text;

      if (today && mins >= today[0] * 60 && mins < today[1] * 60) {
        isOpen = true;
        text = 'Открыто до ' + hhmm(today[1]);
      } else if (today && mins < today[0] * 60) {
        text = 'Откроем сегодня в ' + hhmm(today[0]);
      } else {
        var nx = nextWorkday(day);
        text = nx.shift === 1
          ? 'Откроем завтра в ' + hhmm(nx.hour)
          : 'Откроем в ' + DAYS[nx.day] + ' в ' + hhmm(nx.hour);
      }

      el.querySelector('span').textContent = text;
      el.classList.toggle('is-open', isOpen);
      el.hidden = false;
    }

    render();
    setInterval(render, 60000);
  })();


  /* ─────────── Быстрая связь ─────────── */
  (function quick() {
    var el = document.getElementById('quick');
    if (!el) return;
    el.hidden = false;

    function update() {
      el.classList.toggle('is-on', window.scrollY > window.innerHeight * 0.7);
    }
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update, { passive: true });
    update();
  })();


  /* ─────────── Форма записи ─────────── */
  (function form() {
    var form   = document.getElementById('bookForm');
    if (!form) return;

    var phone  = document.getElementById('fPhone');
    var name   = document.getElementById('fName');
    var agree  = document.getElementById('fAgree');
    var submit = document.getElementById('formSubmit');
    var status = document.getElementById('formStatus');

    /* — маска телефона — */
    phone.addEventListener('input', function () {
      var d = phone.value.replace(/\D/g, '');
      if (d[0] === '8') d = '7' + d.slice(1);
      if (d[0] !== '7') d = '7' + d;
      d = d.slice(0, 11);

      var out = '+7';
      if (d.length > 1) out += ' (' + d.slice(1, 4);
      if (d.length >= 5) out += ') ' + d.slice(4, 7);
      if (d.length >= 8) out += '-' + d.slice(7, 9);
      if (d.length >= 10) out += '-' + d.slice(9, 11);
      phone.value = out;
    });
    phone.addEventListener('focus', function () {
      if (!phone.value) phone.value = '+7 (';
    });

    /* — вывод ошибки под полем — */
    function setErr(input, msg) {
      var field = input.closest('.field') || input.parentElement;
      var box   = field.querySelector('[data-err]') ||
                  form.querySelector('[data-err="agree"]');
      field.classList.toggle('has-err', !!msg);
      if (box) {
        box.textContent = msg || '';
        box.classList.toggle('is-on', !!msg);
      }
      return !msg;
    }

    function validate() {
      var ok = true;
      ok = setErr(name, name.value.trim().length >= 2 ? '' : 'Как к вам обращаться?') && ok;
      ok = setErr(phone, phone.value.replace(/\D/g, '').length === 11 ? '' : 'Нужен полный номер') && ok;

      var agreeBox = form.querySelector('[data-err="agree"]');
      if (!agree.checked) {
        agreeBox.textContent = 'Без согласия мы не сможем перезвонить';
        agreeBox.classList.add('is-on');
        ok = false;
      } else {
        agreeBox.textContent = '';
        agreeBox.classList.remove('is-on');
      }
      return ok;
    }

    [name, phone].forEach(function (el) {
      el.addEventListener('input', function () { setErr(el, ''); });
    });
    agree.addEventListener('change', function () {
      var b = form.querySelector('[data-err="agree"]');
      if (agree.checked) { b.textContent = ''; b.classList.remove('is-on'); }
    });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      status.className = 'form__status';
      status.textContent = '';

      if (!validate()) {
        status.textContent = 'Проверьте отмеченные поля';
        status.classList.add('is-err');
        return;
      }

      submit.disabled = true;
      submit.textContent = 'Отправляем…';

      var data = Object.fromEntries(new FormData(form).entries());

      /* ─────────────────────────────────────────────────────────
         ЗАГЛУШКА ОТПРАВКИ.
         Чтобы заявки реально приходили, подключите приёмник форм —
         например Formspree или Web3Forms — и замените блок ниже на:

           fetch('https://formspree.io/f/ВАШ_ID', {
             method: 'POST',
             headers: { 'Accept': 'application/json' },
             body: new FormData(form)
           })
             .then(function (r) { if (!r.ok) throw new Error(); done(); })
             .catch(fail);
         ───────────────────────────────────────────────────────── */
      console.log('Заявка:', data);

      setTimeout(function () {
        form.reset();
        submit.disabled = false;
        submit.textContent = 'Отправить заявку';
        status.className = 'form__status is-ok';
        status.textContent = 'Заявка принята. Перезвоним в рабочее время и подберём удобное окно.';
      }, 900);
    });
  })();


  /* ─────────── Год в подвале ─────────── */
  (function year() {
    var el = document.querySelector('.footer__row--btm .label--dim');
    if (el) el.textContent = '© ' + new Date().getFullYear() + ' ЛаСТОчка11';
  })();

})();
