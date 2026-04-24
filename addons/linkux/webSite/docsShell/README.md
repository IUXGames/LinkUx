# DocShell

Sistema modular de documentación que convierte archivos `.md` en sitios de docs navegables, sin depender de ningún `.css` ni `.html` predefinido.

---

## Índice

1. [Qué incluye el paquete](#qué-incluye-el-paquete)
2. [Cómo funciona en 30 segundos](#cómo-funciona-en-30-segundos)
3. [Formato del archivo Markdown](#formato-del-archivo-markdown)
4. [Integración en tu HTML](#integración-en-tu-html)
5. [Configuración de DocShell](#configuración-de-docshell)
6. [Cambio de idiomas](#cambio-de-idiomas)
7. [Barra de búsqueda (DocShellSearch)](#barra-de-búsqueda-docshellsearch)
8. [Referencia de clases CSS](#referencia-de-clases-css)
9. [API de eventos](#api-de-eventos)
10. [API pública de DocShell](#api-pública-de-docshell)
11. [Dependencias](#dependencias)
12. [Ejemplos completos](#ejemplos-completos)

---

## Qué incluye el paquete

```
doc-shell/
├── doc-shell.js          # Motor principal (parsing, render, navegación, i18n)
├── doc-shell-search.js   # Módulo de búsqueda (indexado + UI de resultados)
└── README.md             # Esta guía
```

Sin archivos `.css`. Sin archivos `.html`. Solo dos scripts que puedes vincular a cualquier página tuya y controlar completamente con tu propio estilo.

---

## Cómo funciona en 30 segundos

1. Escribes tu documentación en un archivo `.md` normal, añadiendo un comentario especial al inicio de cada sección para indicar dónde empieza cada "página":

```markdown
<!-- doc-shell:page slug="introduccion" -->

# Introducción

Aquí va el contenido de esta sección...

<!-- doc-shell:page slug="instalacion" -->

## Instalación

Pasos para instalar...
```

2. En tu HTML, creas un contenedor vacío y cargas los dos scripts:

```html
<div id="mi-docs"></div>

<script src="doc-shell.js"></script>
<script>
  const ds = new DocShell({
    container: '#mi-docs',
    source: 'docs/mi-proyecto.md',
  });
</script>
```

3. DocShell genera toda la estructura HTML dentro del contenedor. Tú aplicas tu propio CSS usando las clases `ds-*` que el sistema asigna a cada elemento.

---

## Formato del archivo Markdown

### El marcador de página

Cada sección independiente debe comenzar con:

```html
<!-- doc-shell:page slug="nombre-unico" -->
```

- `slug` debe ser único dentro del archivo.
- El slug se usa como identificador de URL (`#nombre-unico`) y como ID del elemento `<section>`.
- El título de la sección en el sidebar se extrae automáticamente del primer encabezado (`#`, `##`, etc.) que aparezca después del marcador.
- Si no hay encabezado, se usa el slug como título.

### Archivo sin marcadores

Si tu archivo `.md` no contiene ningún marcador, DocShell trata todo el archivo como una sola página con slug `main`.

### Elementos soportados

DocShell soporta todos los elementos estándar de Markdown:

| Elemento Markdown         | Clase CSS generada               |
|---------------------------|----------------------------------|
| `# Título`                | `ds-h1`                          |
| `## Subtítulo`            | `ds-h2`                          |
| `### Sección`             | `ds-h3`                          |
| `#### Sub-sección`        | `ds-h4`                          |
| `##### Nivel 5`           | `ds-h5`                          |
| `###### Nivel 6`          | `ds-h6`                          |
| Párrafo de texto          | `ds-p`                           |
| Lista `- item`            | `ds-ul` + `ds-li`                |
| Lista `1. item`           | `ds-ol` + `ds-li`                |
| Tabla                     | `ds-table-wrapper` > `ds-table`  |
| Encabezado de tabla       | `ds-thead` > `ds-tr` > `ds-th`   |
| Cuerpo de tabla           | `ds-tbody` > `ds-tr` > `ds-td`   |
| Bloque de código          | `ds-code-block-wrapper`          |
| Cabecera del bloque       | `ds-code-block-header`           |
| Nombre del lenguaje       | `ds-code-lang`                   |
| Botón copiar              | `ds-code-copy-btn`               |
| `<pre>`                   | `ds-pre`                         |
| `<code>` (bloque)         | `ds-code-block language-{lang}`  |
| `` `código inline` ``     | `ds-code-inline`                 |
| `> Cita`                  | `ds-blockquote`                  |
| `---`                     | `ds-hr`                          |
| `[enlace](url)`           | `ds-a`                           |
| `![imagen](url)`          | `ds-img`                         |
| `**negrita**`             | `ds-strong`                      |
| `*cursiva*`               | `ds-em`                          |
| `~~tachado~~`             | `ds-del`                         |

### Shields / badges

Los badges de Shields.io (o cualquier imagen inline) se renderizan como `<img class="ds-img">`. Puedes darles estilo específico con `.ds-p .ds-img` si los usas dentro de párrafos.

---

## Integración en tu HTML

DocShell **no requiere** una estructura HTML específica. Solo necesitas:

1. Un elemento contenedor con un `id` (o cualquier selector CSS).
2. Incluir `doc-shell.js` (y opcionalmente `doc-shell-search.js`).
3. Inicializar con `new DocShell({...})`.

### Estructura generada

Al inicializar, DocShell **reemplaza** el contenido del contenedor con:

```html
<div class="ds-root" data-lang="es">
  <aside class="ds-sidebar">
    <!-- botones de idioma (si hay múltiples) -->
    <div class="ds-lang-switcher">
      <button class="ds-lang-btn ds-lang-btn--active" data-lang="es">ES</button>
      <button class="ds-lang-btn" data-lang="en">EN</button>
    </div>

    <!-- slot de búsqueda (donde monta DocShellSearch) -->
    <div class="ds-search-slot" id="ds-search-slot"></div>

    <!-- navegación lateral -->
    <nav class="ds-nav" aria-label="Documentation">
      <ul class="ds-nav-list">
        <li class="ds-nav-item ds-nav-item--active" data-slug="introduccion">
          <a class="ds-nav-link ds-nav-link--active" href="#introduccion">Introducción</a>
        </li>
        <li class="ds-nav-item" data-slug="instalacion">
          <a class="ds-nav-link" href="#instalacion">Instalación</a>
        </li>
      </ul>
    </nav>
  </aside>

  <main class="ds-main" role="main">
    <!-- cada sección es una <section> independiente; solo la activa es visible -->
    <section class="ds-page" id="introduccion" data-slug="introduccion">
      <div class="ds-page-inner">
        <!-- contenido renderizado del markdown -->
      </div>
    </section>
    <section class="ds-page" id="instalacion" data-slug="instalacion" hidden>
      <div class="ds-page-inner">
        <!-- ... -->
      </div>
    </section>
  </main>
</div>
```

> Las secciones inactivas llevan el atributo `hidden`. La sección activa no lo tiene.

---

## Configuración de DocShell

```js
const ds = new DocShell({
  // ─── Requerido (uno de los dos) ─────────────────────────────────────────────
  container:    '#mi-docs',   // Selector CSS o elemento DOM del contenedor.

  source:       'docs/mi-proyecto.md', // Archivo .md único (sin i18n).
  // — O bien —
  langs: {
    es: 'docs/es.md',
    en: 'docs/en.md',
  },
  defaultLang: 'es',          // Idioma inicial. Default: primer idioma de `langs`.

  // ─── Opcionales ─────────────────────────────────────────────────────────────
  prefix:       'ds-',        // Prefijo de las clases CSS. Default: 'ds-'
  highlight:    true,         // Activar highlight.js si está disponible. Default: true
  copyLabel:    'Copiar',     // Texto del botón de copiar código.
  copiedLabel:  '¡Copiado!',  // Texto tras copiar (dura 2 segundos).

  // ─── Callbacks ──────────────────────────────────────────────────────────────
  onReady:      (ds)             => { /* se ejecuta al terminar la primera carga */ },
  onPageChange: (slug, page)     => { /* se ejecuta al navegar entre páginas    */ },
  onLangChange: (lang)           => { /* se ejecuta al cambiar de idioma        */ },
});
```

### Prefijo personalizado

Si usas un prefijo diferente (por ejemplo `'doc-'`), **todas** las clases CSS cambian en consecuencia: `doc-root`, `doc-sidebar`, `doc-h1`, etc. Esto permite aislar DocShell de otros componentes o usar múltiples instancias en la misma página sin conflictos de clases.

---

## Cambio de idiomas

### Configuración

Define un mapa `langs` con clave de idioma → ruta del archivo `.md`:

```js
const ds = new DocShell({
  container: '#docs',
  langs: {
    es: 'docs/es.md',
    en: 'docs/en.md',
    fr: 'docs/fr.md',
  },
  defaultLang: 'es',
});
```

Si hay más de un idioma, DocShell genera automáticamente un `<div class="ds-lang-switcher">` en el sidebar con un botón por idioma.

### Cambio programático

```js
// Cambiar a inglés
await ds.setLang('en');
```

DocShell:
1. Descarga el nuevo archivo `.md`.
2. Re-parsea y re-renderiza toda la interfaz.
3. Intenta navegar a la misma página (mismo slug) en el nuevo idioma.

### Botones personalizados de idioma

Si prefieres construir tus propios controles en lugar de usar los que genera DocShell, desactiva el switcher usando un único idioma en `langs` y llama `ds.setLang()` desde tus propios botones.

---

## Barra de búsqueda (DocShellSearch)

### Montaje rápido

```js
// Inicializa DocShell primero
const ds = new DocShell({ container: '#docs', source: 'docs/mi.md' });

// Luego inicializa DocShellSearch y móntalo en el slot de búsqueda
const search = new DocShellSearch(ds, {
  placeholder:   'Buscar en la documentación…',
  noResultsText: 'Sin resultados.',
});

// Espera a que DocShell esté listo antes de montar
ds.on('ready', () => {
  search.mount(ds.getSearchSlot());
});
```

`ds.getSearchSlot()` devuelve el `<div class="ds-search-slot">` que DocShell reserva en el sidebar. Puedes pasar cualquier otro elemento si prefieres colocar la búsqueda en otro lugar de tu página.

### Opciones de DocShellSearch

```js
const search = new DocShellSearch(ds, {
  minLength:     2,                             // Mínimo de caracteres para buscar.
  maxResults:    30,                            // Máximo de resultados en el dropdown.
  snippetPad:    40,                            // Caracteres antes del match en el snippet.
  snippetLen:    120,                           // Caracteres después del match en el snippet.
  placeholder:   'Buscar…',                    // Placeholder del input.
  noResultsText: 'No se encontraron resultados.',
  prefix:        'ds-',                         // Hereda automáticamente del prefijo de DocShell.
  onNavigate:    (slug) => { /* callback al seleccionar un resultado */ },
});
```

### Estructura HTML generada por la búsqueda

```html
<div class="ds-search-wrapper" role="search">
  <input class="ds-search-input" type="search" placeholder="Buscar…"
         aria-autocomplete="list" aria-expanded="false">

  <!-- se muestra solo cuando hay resultados o la query es válida -->
  <div class="ds-search-dropdown" role="listbox">

    <div class="ds-search-item ds-search-item--h2" data-slug="instalacion">
      <div class="ds-search-item-meta">
        <span class="ds-search-item-page">Instalación</span>
        <span class="ds-search-item-section">Paso 1 — Copiar el addon</span>
        <span class="ds-search-item-type">h2</span>
      </div>
      <div class="ds-search-item-snippet">
        …copia la carpeta en <mark class="ds-search-mark">res://addons/</mark>…
      </div>
    </div>

    <!-- sin resultados -->
    <div class="ds-search-no-results">Sin resultados.</div>

  </div>
</div>
```

### Clases del tipo de resultado

| Clase                       | Cuándo aparece                        |
|-----------------------------|---------------------------------------|
| `ds-search-item--h1`        | Resultado es un encabezado `#`        |
| `ds-search-item--h2`        | Resultado es un encabezado `##`       |
| `ds-search-item--h3` … `h6` | Encabezados de nivel inferior         |
| `ds-search-item--text`      | Resultado en un párrafo/lista         |
| `ds-search-item--table`     | Resultado en una celda de tabla       |
| `ds-search-item--code`      | Resultado dentro de un bloque código  |
| `ds-search-item--focused`   | Ítem con foco por teclado (↑ ↓)       |

### Navegación por teclado en la búsqueda

| Tecla    | Acción                              |
|----------|-------------------------------------|
| `↓`      | Mover foco al siguiente resultado   |
| `↑`      | Mover foco al resultado anterior    |
| `Enter`  | Navegar a la página del resultado   |
| `Escape` | Cerrar el dropdown                  |
| `Tab`    | Cerrar el dropdown                  |

### Uso de la API de búsqueda sin UI

Si quieres construir tu propia interfaz de búsqueda, usa directamente el método `search()`:

```js
const search = new DocShellSearch(ds);
ds.on('ready', () => search.buildIndex());

// Buscar programáticamente
const results = search.search('comando');
results.forEach(r => {
  console.log(r.slug, r.section, r.snippet, r.score);
});
```

---

## Referencia de clases CSS

Lista completa de todas las clases que DocShell genera. Con el prefijo por defecto `ds-`:

### Layout

| Clase                  | Elemento                                      |
|------------------------|-----------------------------------------------|
| `ds-root`              | Raíz de toda la interfaz                      |
| `ds-sidebar`           | Sidebar izquierdo (nav + search + lang)       |
| `ds-main`              | Contenedor principal del contenido            |
| `ds-page`              | `<section>` de cada página (una por slug)     |
| `ds-page-inner`        | Wrapper interno del contenido de la página    |

### Navegación

| Clase                  | Elemento                                      |
|------------------------|-----------------------------------------------|
| `ds-nav`               | Elemento `<nav>` del sidebar                  |
| `ds-nav-list`          | `<ul>` de la lista de páginas                 |
| `ds-nav-item`          | `<li>` de cada página                         |
| `ds-nav-item--active`  | `<li>` de la página activa                    |
| `ds-nav-link`          | `<a>` de cada ítem                            |
| `ds-nav-link--active`  | `<a>` activo (página visible)                 |

### Cambio de idioma

| Clase                  | Elemento                                      |
|------------------------|-----------------------------------------------|
| `ds-lang-switcher`     | Contenedor de botones de idioma               |
| `ds-lang-btn`          | Botón de cada idioma                          |
| `ds-lang-btn--active`  | Botón del idioma activo                       |

### Contenido Markdown

| Clase                      | Elemento                                  |
|----------------------------|-------------------------------------------|
| `ds-h1` … `ds-h6`          | Encabezados                               |
| `ds-p`                     | Párrafos                                  |
| `ds-ul`                    | Lista desordenada                         |
| `ds-ol`                    | Lista ordenada                            |
| `ds-li`                    | Ítem de lista                             |
| `ds-blockquote`            | Cita en bloque                            |
| `ds-hr`                    | Línea horizontal                          |
| `ds-strong`                | Texto en negrita                          |
| `ds-em`                    | Texto en cursiva                          |
| `ds-del`                   | Texto tachado                             |
| `ds-a`                     | Enlace                                    |
| `ds-img`                   | Imagen                                    |

### Tablas

| Clase                      | Elemento                                  |
|----------------------------|-------------------------------------------|
| `ds-table-wrapper`         | `<div>` envolvente (para scroll horizontal)|
| `ds-table`                 | `<table>`                                 |
| `ds-thead`                 | `<thead>`                                 |
| `ds-tbody`                 | `<tbody>`                                 |
| `ds-tr`                    | `<tr>`                                    |
| `ds-th`                    | `<th>`                                    |
| `ds-td`                    | `<td>`                                    |

### Bloques de código

| Clase                       | Elemento                                 |
|-----------------------------|------------------------------------------|
| `ds-code-block-wrapper`     | Contenedor del bloque completo           |
| `ds-code-block-header`      | Cabecera (nombre del lenguaje + botón)   |
| `ds-code-lang`              | `<span>` con el nombre del lenguaje      |
| `ds-code-copy-btn`          | Botón "Copiar"                           |
| `ds-code-copy-btn--copied`  | Modificador aplicado 2s tras copiar      |
| `ds-pre`                    | `<pre>`                                  |
| `ds-code-block`             | `<code>` del bloque (más `language-xyz`) |
| `ds-code-inline`            | `<code>` inline                          |

### Búsqueda

| Clase                       | Elemento                                 |
|-----------------------------|------------------------------------------|
| `ds-search-slot`            | Contenedor donde monta DocShellSearch    |
| `ds-search-wrapper`         | Wrapper del input + dropdown             |
| `ds-search-input`           | Input de búsqueda                        |
| `ds-search-dropdown`        | Dropdown de resultados                   |
| `ds-search-item`            | Cada resultado                           |
| `ds-search-item--{type}`    | Modificador por tipo (h1, text, etc.)    |
| `ds-search-item--focused`   | Resultado con foco por teclado           |
| `ds-search-item-meta`       | Fila superior: página + sección + tipo   |
| `ds-search-item-page`       | Nombre de la página del resultado        |
| `ds-search-item-section`    | Encabezado más cercano al resultado      |
| `ds-search-item-type`       | Etiqueta de tipo (h2, text, table…)      |
| `ds-search-item-snippet`    | Fragmento de texto con el match          |
| `ds-search-mark`            | `<mark>` alrededor del texto encontrado  |
| `ds-search-no-results`      | Mensaje de sin resultados                |

---

## API de eventos

```js
// Escuchar un evento
ds.on('ready',      ({ lang, pages }) => { ... });
ds.on('pageChange', ({ slug, page }) => { ... });
ds.on('langChange', ({ lang })       => { ... });

// Quitar un listener
ds.off('pageChange', miCallback);
```

| Evento        | Datos del evento                      | Cuándo se dispara                         |
|---------------|---------------------------------------|-------------------------------------------|
| `ready`       | `{ lang, pages[] }`                   | Tras cargar y renderizar el archivo .md   |
| `pageChange`  | `{ slug, page }`                      | Al navegar a una página                   |
| `langChange`  | `{ lang }`                            | Al cambiar de idioma                      |

---

## API pública de DocShell

```js
// Carga / recarga un archivo .md (lang = clave en el mapa `langs`, o null para `source`)
await ds.load('es');

// Navega a una página por su slug
ds.navigate('instalacion');

// Cambia de idioma y recarga el .md correspondiente
await ds.setLang('en');

// Vuelve a aplicar highlight.js (útil al cambiar tema claro/oscuro)
ds.rehighlight();

// Obtener información
ds.getPages();          // Array de { slug, title, md, html, text }
ds.getCurrentSlug();    // Slug de la página visible
ds.getCurrentLang();    // Idioma activo ('es', 'en', ...)
ds.getLangs();          // ['es', 'en', ...]
ds.getContainer();      // Elemento DOM del contenedor
ds.getSearchSlot();     // Elemento DOM del slot de búsqueda
```

### API pública de DocShellSearch

```js
// Construir/reconstruir el índice
search.buildIndex();

// Buscar (devuelve array de resultados)
const results = search.search('comando');
// Cada resultado: { slug, pageTitle, section, type, snippet, score }

// Generar HTML de snippet con highlights
const html = search.highlightSnippet('texto con match', 'match');

// Montar la UI en un elemento
search.mount(ds.getSearchSlot());
search.mount('#mi-buscador');
search.mount(document.getElementById('buscador'));

// Info del índice
search.getIndexSize(); // número total de entradas indexadas
search.getIndex();     // copia del array de índice
```

---

## Dependencias

DocShell funciona con dependencias opcionales para maximizar la compatibilidad:

### marked.js (altamente recomendado)

Versión: **4.x** (la más compatible con la API de renderer de DocShell).

```html
<script src="https://cdn.jsdelivr.net/npm/marked@4/marked.min.js"></script>
```

Sin marked.js, DocShell muestra el contenido raw en un `<pre>` como fallback.

### highlight.js (recomendado para documentación técnica)

```html
<!-- CSS del tema (elige el que prefieras, o uno propio) -->
<link rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">

<!-- Script -->
<script
  src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js">
</script>
```

DocShell detecta automáticamente si `window.hljs` está disponible y aplica `hljs.highlightElement()` a todos los bloques de código tras renderizar. Si no quieres highlight, pasa `highlight: false` en la configuración.

Si cambias el tema de highlight.js dinámicamente (por ejemplo para modo oscuro/claro), llama `ds.rehighlight()` para reaplicar.

---

## Ejemplos completos

### Ejemplo 1 — Fuente única, sin i18n

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Mi Documentación</title>
  <link rel="stylesheet" href="mi-tema.css">
  <!-- highlight.js (opcional) -->
  <link rel="stylesheet"
    href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
</head>
<body>

  <div id="docs"></div>

  <!-- marked.js -->
  <script src="https://cdn.jsdelivr.net/npm/marked@4/marked.min.js"></script>
  <!-- highlight.js -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <!-- DocShell -->
  <script src="doc-shell.js"></script>
  <script src="doc-shell-search.js"></script>

  <script>
    const ds = new DocShell({
      container:    '#docs',
      source:       'docs/mi-proyecto.md',
      copyLabel:    'Copiar',
      copiedLabel:  '¡Listo!',
    });

    const search = new DocShellSearch(ds, {
      placeholder:   'Buscar en la documentación…',
      noResultsText: 'Sin resultados.',
    });

    ds.on('ready', () => search.mount(ds.getSearchSlot()));
  </script>
</body>
</html>
```

---

### Ejemplo 2 — Múltiples idiomas

```html
<script>
  const ds = new DocShell({
    container:   '#docs',
    langs: {
      es: 'docs/es.md',
      en: 'docs/en.md',
    },
    defaultLang:  'es',
    copyLabel:    'Copiar',
    copiedLabel:  '¡Copiado!',
    onLangChange: (lang) => {
      document.documentElement.lang = lang;
    },
  });

  const search = new DocShellSearch(ds, {
    placeholder: ds.getCurrentLang() === 'es' ? 'Buscar…' : 'Search…',
  });

  ds.on('ready', () => search.mount(ds.getSearchSlot()));
</script>
```

---

### Ejemplo 3 — Prefijo personalizado

Si usas un prefijo distinto a `ds-`, solo necesitas actualizar tus selectores CSS:

```js
const ds = new DocShell({
  container: '#docs',
  source:    'docs/mi.md',
  prefix:    'myproject-',  // todas las clases serán myproject-root, myproject-h1, etc.
});
```

```css
/* Tu CSS usará las mismas clases pero con tu prefijo */
.myproject-root { display: flex; }
.myproject-sidebar { width: 280px; }
/* ... */
```

---

### Ejemplo 4 — Botones de idioma propios

Si quieres construir tus propios botones de idioma fuera del sidebar:

```html
<header>
  <button onclick="ds.setLang('es')">ES</button>
  <button onclick="ds.setLang('en')">EN</button>
</header>
<div id="docs"></div>
```

```js
const ds = new DocShell({
  container:   '#docs',
  // Solo un idioma en `langs` = DocShell NO genera el switcher automático
  langs: { es: 'docs/es.md', en: 'docs/en.md' },
  defaultLang: 'es',
});
```

---

### Ejemplo 5 — Instancias múltiples en la misma página

Puedes tener varias instancias independientes en la misma página (por ejemplo, documentación de diferentes productos):

```js
const dsA = new DocShell({
  container: '#docs-producto-a',
  source:    'docs/producto-a.md',
  prefix:    'dsa-',
});

const dsB = new DocShell({
  container: '#docs-producto-b',
  source:    'docs/producto-b.md',
  prefix:    'dsb-',
});
```

Al usar prefijos diferentes, no habrá colisiones de clases CSS entre instancias.

---

## Notas y buenas prácticas

- Los archivos `.md` son descargados vía `fetch()`. Para desarrollo local, necesitarás un servidor HTTP simple (por ejemplo `npx serve .` o la extensión Live Server de VS Code); abrir el HTML como `file://` bloqueará el fetch por restricciones CORS del navegador.
- DocShell guarda el estado de navegación en el hash de la URL (`#slug`). El botón atrás del navegador funciona de forma nativa.
- La barra de búsqueda indexa **todo el contenido** del archivo `.md` incluyendo código, tablas y encabezados. Cuanto más estructurado esté el documento, mejor serán los resultados.
- Para temas de highlight.js claros/oscuros, cambia el `<link>` del CSS de hljs y llama `ds.rehighlight()`.
- Si necesitas añadir contenido dinámico a una página (por ejemplo, iframes o componentes interactivos), usa `ds.on('pageChange', ...)` para inyectarlos después de que la sección sea visible.
