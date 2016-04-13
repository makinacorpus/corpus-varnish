{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}

prepreqs-{{cfg.name}}:
  pkg.installed:
    - pkgs:
      - varnish
    - watch_in:
      - service: enable-service-varnish-{{ cfg.name }}

# allow original systemd service
enable-service-varnish-{{ cfg.name }}:
  service.running:
    - name: varnish
    - enable: True
    - reload : False

{#
This produce the default layout

  /project     : sources
    etc/       : configuration
    bin/       : binary (our varnishd wrapper)
    var        link --> ../data/var

  /data    : persistent data
    var/   : runtime files (cache files)
      log/
      run/
      cache/

#}

{{cfg.name}}-dirs:
  file.directory:
    - makedirs: true
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - mode: 770
    - watch:
      - pkg: prepreqs-{{cfg.name}}
    - names:
      - {{cfg.data_root}}/etc
      - {{cfg.data_root}}/bin
      - {{cfg.data_root}}/var
      - {{cfg.data_root}}/var/log
      - {{cfg.data_root}}/var/run
      - {{cfg.data_root}}/var/cache

{% for d in ['var'] %}
{{cfg.name}}-l-dirs{{d}}:
  file.symlink:
    - name: {{cfg.project_root}}/{{d}}
    - target: {{cfg.data_root}}/{{d}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - watch:
      - file: {{cfg.name}}-dirs
    - watch:
      - pkg: prepreqs-{{cfg.name}}
{% endfor %}

{% for d in ['log'] %}
{{cfg.name}}-l-var-dirs{{d}}:
  file.symlink:
    - name: {{cfg.project_root}}/{{d}}
    - target: {{cfg.data_root}}/var/{{d}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - watch:
      - file: {{cfg.name}}-dirs
{% endfor %}

# Fix Ubuntu systemd startup which
# does not read /etc/default/varnish
# but still use it to pilot varishadm on reload
varnish-systemd-override-dir:
  file.directory:
    - makedirs: true
    - user: root
    - group: root
    - mode: 770
    - names:
      - /etc/systemd/system/varnish.service.d

varnish-systemd-config:
  file.managed:
    - source: salt://makina-projects/{{cfg.name}}/files/etc/systemd/system/varnish.service
    - names: 
      - /etc/systemd/system/varnish.service.d/override.conf
    - template: jinja
    - mode: 640
    - user: root
    - group: root
    - defaults:
        cfg: "{{cfg.name}}"
    - require:
      - file: varnish-systemd-override-dir
      - pkg: prepreqs-{{cfg.name}}
    - watch_in:
      - service: enable-service-varnish-{{ cfg.name }}

varnish-systemd-reload-conf:
  cmd.run:
    - name: "systemctl daemon-reload"
    - onchanges:
      - file: varnish-systemd-config

varnish-service-restart:
  cmd.run:
    - name: "service varnish restart"
    - require:
      {# THAT'S THE strange thing, we need a service defined to be able to start #}
      - file: init-varnish-service-config
    - watch:
      - cmd: varnish-systemd-reload-conf
      - file: varnish-systemd-sbin-wrapper
      - file: varnish-service-defaults


varnish-systemd-sbin-wrapper:
  file.managed:
    - source: salt://makina-projects/{{cfg.name}}/files/usr/bin/varnishd-wrapper.sh
    - names:
      - /usr/bin/varnishd-wrapper.sh
    - template: jinja
    - mode: 700
    - user: root
    - group: root
    - defaults:
        cfg: "{{cfg.name}}"
    - watch_in:
      - service: enable-service-varnish-{{ cfg.name }}

varnish-service-defaults:
  file.managed:
    - source: salt://makina-projects/{{cfg.name}}/files/etc/default/varnish
    - names:
      - /etc/default/varnish
    - template: jinja
    - mode: 640
    - user: root
    - group: root
    - defaults:
        cfg: "{{cfg.name}}"
    - watch_in:
      - service: enable-service-varnish-{{ cfg.name }}

{# this state  came from 100_configuration.sls but we need it on first install also #}
init-varnish-service-config:
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
