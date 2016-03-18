{% set cfg = opts['ms_project'] %}
{# export macro to callees #}
{% set locs = salt['mc_locations.settings']() %}
{% set lsettings = cfg.data.local_settings %}
{{cfg.name}}-restricted-perms:
  file.managed:
    - name: {{cfg.project_dir}}/global-reset-perms.sh
    - mode: 750
    - user: {% if not cfg.no_user%}{{cfg.user}}{% else -%}root{% endif %}
    - group: {{cfg.group}}
    - contents: |
            #!/usr/bin/env bash
            varnishgroup="{{cfg.group}}"
            groupadd -r $varnishgroup || /bin/true
            gpasswd -a {{cfg.user}} $varnishgroup || /bin/true
            gpasswd -a varnish $datagroup || /bin/true
            # be sure to remove POSIX acls support
            setfacl -P -R -b -k "{{cfg.project_dir}}"
            "{{locs.resetperms}}" -q --no-acls\
              --user root --group "{{cfg.group}}" \
              --dmode '0770' --fmode '0770' \
              --paths "{{cfg.pillar_root}}";
            # general loop (ownership and setgid for directories)
            find -H \
              "{{cfg.project_root}}" \
              "{{cfg.data_root}}" {%if not cfg.remote_less %}"{{cfg.git_root}}"{% endif %} \
              \(\
                \(     -type f -and \( -not -user {{cfg.user}} -or -not -group {{cfg.group}}                      \) \)\
                -or \( -type d -and \( -not -user {{cfg.user}} -or -not -group {{cfg.group}} -or -not -perm -2000 \) \)\
              \)\
              |\
              while read i;do
                if [ ! -h "${i}" ];then
                  if [ -d "${i}" ];then
                    chmod g-s "${i}"
                    chown {{cfg.user}}:$datagroup "${i}"
                    chmod g+s "${i}"
                  elif [ -f "${i}" ];then
                    chown {{cfg.user}}:$datagroup "${i}"
                  fi
                fi
             done
             find "{{cfg.data_root}}/var" "{{cfg.data_root}}/var/run" \
               -maxdepth 1 -mindepth 1 | \
             egrep '((/(run|cache|log))|sock)'|while read f;do
                {{locs.resetperms}} -q --no-acls \
                  --fmode 771 --dmode 2771 \
                  -u {{cfg.user}} -g {{cfg.group}} \
                  --paths "$f";
             done
             cd '{{cfg.data_root}}/var'
            "{{locs.resetperms}}" -q --no-acls --no-recursive\
              --user root --group root --dmode '0555' --fmode '0555' \
              --paths "{{cfg.project_dir}}/global-reset-perms.sh" \
              --paths "{{cfg.project_root}}"/.. \
              --paths "{{cfg.project_root}}"/../..;
  cmd.run:
    - name: {{cfg.project_dir}}/global-reset-perms.sh
    - cwd: {{cfg.project_root}}
    - user: root
    - watch:
      - file: {{cfg.name}}-restricted-perms

{{cfg.name}}-fixperms:
  file.managed:
    - name: /etc/cron.d/{{cfg.name.replace('.', '_')}}-fixperms
    - user: root
    - mode: 744
    - contents: |
                {{cfg.data.fixperms_cron_periodicity}} root {{cfg.project_dir}}/global-reset-perms.sh

