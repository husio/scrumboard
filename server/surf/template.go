package surf

import (
	"bytes"
	"fmt"
	"html/template"
	"net/http"
	"runtime/debug"
	"sync"
)

type Renderer interface {
	Render(w http.ResponseWriter, code int, templateName string, content interface{})
	RenderDefault(w http.ResponseWriter, code int)
}

type TemplateRenderer struct {
	Debug bool
	tglob string

	parseErr  error
	templates map[string]*template.Template

	buffers sync.Pool
}

var _ Renderer = (*TemplateRenderer)(nil)

func LoadTemplates(templatesPath string) *TemplateRenderer {
	r := &TemplateRenderer{
		Debug:     false,
		tglob:     templatesPath,
		templates: nil,
		parseErr:  nil,
		buffers: sync.Pool{
			New: func() interface{} { return bytes.NewBuffer(nil) },
		},
	}

	r.loadTemplates()
	return r
}

func (r *TemplateRenderer) loadTemplates() {
	t, err := defaultTemplates().ParseGlob(r.tglob)
	r.parseErr = err

	if err != nil {
		// if failed to parse user provided templates, fallback to
		// defaults only, because they are providing templates that are
		// expected to always be present
		t = defaultTemplates()
	}
	r.templates = make(map[string]*template.Template)
	for _, t := range t.Templates() {
		r.templates[t.Name()] = t
	}
}

func (r *TemplateRenderer) Render(w http.ResponseWriter, code int, templateName string, content interface{}) {
	if r.Debug {
		r.loadTemplates()
	}

	if r.parseErr != nil {
		r.renderError(w, r.parseErr)
		return
	}

	// render template before writing response to handle failures correctly
	// and avoid writing response code twice
	buf := r.buffers.Get().(*bytes.Buffer)
	defer func() {
		buf.Reset()
		r.buffers.Put(buf)
	}()

	tmpl, ok := r.templates[templateName]
	if !ok {
		r.renderError(w, fmt.Errorf("template %q does not exist", templateName))
		return
	}
	if err := tmpl.Execute(buf, content); err != nil {
		r.renderError(w, err)
		return
	}

	w.WriteHeader(code)
	buf.WriteTo(w)
}

func (r *TemplateRenderer) RenderDefault(w http.ResponseWriter, code int) {
	content := stdContent{
		StatusCode: code,
		Title:      http.StatusText(code),
	}

	templateName := "default.tmpl" // always present

	if code == http.StatusInternalServerError && r.Debug {
		content.Stack = string(debug.Stack())
		templateName = "error_debug.tmpl"
	} else if code >= 400 {
		if n := fmt.Sprintf("error_%d.tmpl", code); r.templates[n] != nil {
			templateName = n
		}
	}

	r.Render(w, code, templateName, &content)
}

func (r *TemplateRenderer) renderError(w http.ResponseWriter, err error) {
	w.WriteHeader(http.StatusInternalServerError)

	content := stdContent{
		StatusCode: http.StatusInternalServerError,
		Title:      http.StatusText(http.StatusInternalServerError),
		Err:        err,
		Stack:      string(debug.Stack()),
	}

	tmpl := r.templates["default.tmpl"]
	if r.Debug {
		tmpl = r.templates["error_debug.tmpl"]
	}
	tmpl.Execute(w, content)
}

type stdContent struct {
	StatusCode int
	Title      string
	Content    string

	// available only in debug mode
	Err   error
	Stack string
}

var defaultTemplates = func() *template.Template {
	return template.Must(template.New("").Parse(`

{{define "-default-header-" -}}
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { max-width:900px; margin:40px auto; padding:0 20px; font-size:16px; line-height:1.6; color:#383838; }
pre  { overflow:auto; }
</style>
{{- end}}


{{define "default.tmpl" -}}
{{template "-default-header-"}}
<title>{{.StatusCode}}: {{.Title}}</title>
<h1>{{.StatusCode}} - {{.Title}}</h1>
{{if .Content}}<p>{{.Content}}</p>{{end}}
{{- end}}


{{define "error_debug.tmpl" -}}
{{template "-default-header-"}}
<style>
body { max-width: 100%; }
pre  { font-size: 13px; background: #333; color: #eee; padding: 20px; }
</style>
<title>{{.StatusCode}}: {{.Title}}</title>
<h1>{{.StatusCode }} - {{.Title}}</h1>
{{if .Content}}<p>{{.Content}}</p>{{end}}
{{if .Err}}
	<h2>Error</h2>
	<pre><code>{{.Err}}</code></pre>
{{end}}
{{if .Stack}}
	<h2>Stack</h2>
	<pre><code>{{.Stack}}</code></pre>
{{end}}
{{- end}}

`))
}
