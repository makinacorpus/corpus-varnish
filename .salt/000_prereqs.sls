{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}
{% set php = salt['mc_php.settings']() %}

include:
  - makina-states.services.php.phpfpm_with_nginx

{% import "makina-states/services/php/macros.sls" as phpm with context %}
{{ phpm.toggle_ext('pgsql') }}
{{ phpm.toggle_ext('pdo_pgsql') }}
prepreqs-{{cfg.name}}:
  pkg.installed:
    - require_in:
      - mc_proxy: makina-php-pre-inst
    - pkgs:
      - varnish

{#
This produce the default layout

  /project     : sources
    etc/       : configuration
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