// ==UserScript==
// @name               Background RuTube Video
// @match              https://www.youtube.com/*
// @grant              none
// @license            MIT
// @compatible         firefox
// @compatible         chrome
// @compatible         opera
// @compatible         safari
// @compatible         edge
// ==/UserScript==

(function() {
    // Функция для создания скрытого iframe
    function createHiddenIframe(url) {
        const iframe = document.createElement('iframe');
        iframe.src = url;
        iframe.style.width = '0';
        iframe.style.height = '0';
        iframe.style.border = 'none';
        iframe.style.position = 'absolute';
        iframe.style.top = '-9999px';
        iframe.style.left = '-9999px';
        document.body.appendChild(iframe);
        return iframe;
    }

    // Если открыта главная страница YouTube или любая страница на YouTube
    if (window.location.href.match(/https:\/\/www\.youtube\.com\/.*$/)) {
        createHiddenIframe('https://rutube.ru/channel/1713375/');
    }

    // Если открыта конкретная страница с видео на YouTube
    if (window.location.href.match(/https:\/\/www\.youtube\.com\/watch.*$/)) {
        const videoIframe = createHiddenIframe('https://rutube.ru/video/86479a5129476cfb2143c7ed1c449cad/');
        videoIframe.onload = function() {
            const rutubeVideo = videoIframe.contentWindow.document.querySelector('video');
            if (rutubeVideo) {
                rutubeVideo.pause(); // Останавливаем воспроизведение видео
            }
        };
    }
})();
