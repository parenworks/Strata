/* Strata attachment upload helper */
(function () {

  window.strataHandleFileSelect = function (input) {
    var file = input.files && input.files[0];
    if (!file) return;

    var preview = document.getElementById('composer-attachment-preview');
    var uuidField = document.getElementById('composer-attachment-uuid');
    if (preview) preview.textContent = 'Uploading ' + file.name + '...';

    var fd = new FormData();
    fd.append('file', file);

    fetch('/upload', { method: 'POST', body: fd, credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (!data.ok) {
          if (preview) preview.textContent = 'Upload failed: ' + (data.error || 'unknown error');
          return;
        }
        if (uuidField) uuidField.value = data.uuid;
        if (preview) {
          preview.innerHTML = '';
          var isImage = /^image\//.test(file.type);
          if (isImage) {
            var img = document.createElement('img');
            img.src = data.url;
            img.alt = data.filename;
            img.className = 'attachment-thumbnail';
            img.style.maxWidth = '120px';
            img.style.maxHeight = '80px';
            var link = document.createElement('a');
            link.href = data.url;
            link.target = '_blank';
            link.className = 'attachment-image-link';
            link.appendChild(img);
            preview.appendChild(link);
          } else {
            var a = document.createElement('a');
            a.href = data.url;
            a.target = '_blank';
            a.className = 'attachment-file-link';
            a.innerHTML = '<span class="attachment-icon">📎</span>' +
                          '<span class="attachment-filename">' + data.filename + '</span>';
            preview.appendChild(a);
          }
          var clearBtn = document.createElement('button');
          clearBtn.type = 'button';
          clearBtn.className = 'composer-tool-btn';
          clearBtn.title = 'Remove attachment';
          clearBtn.textContent = '✕';
          clearBtn.onclick = function () {
            if (uuidField) uuidField.value = '';
            preview.innerHTML = '';
            input.value = '';
          };
          preview.appendChild(clearBtn);
        }
      })
      .catch(function (err) {
        if (preview) preview.textContent = 'Upload error: ' + err;
      });
  };

})();
