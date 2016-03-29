{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
varnish-service-config:
  file.managed:
    - source: salt://makina-projects/{{cfg.name}}/files/etc/varnish/varnish.vcl
    - names:
      - {{cfg.project_root}}/etc/{{cfg.name}}.vcl
    - template: jinja
    - mode: 640
    - user: "{{cfg.user}}"
    - group: "{{cfg.group}}"
    - defaults:
        cfg: "{{cfg.name}}"
    - watch_in:
      - cmd: varnish-reloader

varnish-reloader:
  cmd.run:
    - name: "service varnish reload"
    - onchanges:
      - file: varnish-service-config
