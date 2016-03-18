{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{{cfg.name}}-vcl-file:
  file.managed:
    - makedirs: true
    - source: salt://makina-projects/{{cfg.name}}/files/varnish.vcl
    - names:
      - {{cfg.project_root}}/etc/varnish.vcl
      # temp debug
      - /etc/varnish/default.vcl
    - template: jinja
    - mode: 640
    - user: "{{cfg.user}}"
    - group: "{{cfg.group}}"
    - defaults:
        cfg: "{{cfg.name}}"

{{cfg.name}}-copy-varnish-secret:
  file.copy:
    - name: {{cfg.project_root}}/etc/secret
    - source: /etc/varnish/secret
    - preserve: true
