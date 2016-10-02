{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set db = data.django_settings.DATABASES.default %}
include:
  - makina-projects.{{cfg.name}}.include.configs


{#- Run the project buildout but skip the maintainance parts #}
{#- Wrap the salt configured setting in a file inputable to buildout #}
{{cfg.name}}-buildout-project:
  cmd.run:
    - name: rsync -aA {{data.app_root}}/deployment/ {{data.app_root}}/deployment.sav/
    - onlyif: test -e {{data.app_root}}/deployment/
  file.absent:
    - name: {{data.app_root}}/deployment
    - watch:
      - cmd: {{cfg.name}}-buildout-project
  buildout.installed:
    - name: {{data.app_root}}
    - config: buildout-salt.cfg
    - buildout_ver: 2
    - python: "{{data.py}}"
    - user: {{cfg.user}}
    - newest: {{{'true': True}.get(cfg.data.buildout.settings.buildout.get('newest', 'false').lower(), False) }}
    - use_vt: true
    - loglevel: info
    - watch:
      - mc_proxy: {{cfg.name}}-configs-after
      - file: {{cfg.name}}-buildout-project


{{cfg.name}}-post:
  file.managed:
    - name: {{data.app_root}}/../cfg-post.sh
    - contents: |
            #!/usr/bin/env bash
            set -ex
            cd $(dirname $0)/bundler
            for i in psycopg2 ipython;do
            if ! ./venv-3.4/bin/python -c "import $i";then
              ./venv-3.4/bin/pip install $i
            fi
            done
            sed -i -r \
              -e "s/(site_owner: )root@localhost/\\1{{data.site_owner}}/g" \
              -e "s/bin\/mailman start.*/bin\/mailman start --force/g" \
              -e "s/Group=mailman.*/Group={{cfg.group}}/g" \
              -e "s/User=mailman.*/User={{cfg.user}}/g" \
              -e "s/su mailman mailman/su {{cfg.user}} {{cfg.group}}/g" \
              -e "s/SecretArchiverAPIKey/{{cfg.data.django_settings.MAILMAN_ARCHIVER_KEY}}/g" \
              deployment/*
            for i in webservice shell database;do
            if ! egrep -q "^\[$i\]" deployment/mailman.cfg;then
            cat >> deployment/mailman.cfg << EOF

            [$i]
            EOF
            fi
            done
            sed -i -r -e "/admin_user:.*/d" -e "/admin_pass:.*/d" -e "/use_ipython:.*/d"\
              deployment/mailman.cfg
            python << EOF
            from __future__ import print_function
            lines = []
            with open('deployment/mailman.cfg') as fic:
              content = fic.read()
              for i in content.splitlines():
                if i.startswith('[shell'):
                  i += """\nuse_ipython: true\n"""
                if i.startswith('[webservice'):
                  i += """\nadmin_user: {{data.django_settings.MAILMAN_REST_API_USER}}\n"""
                  i += """\nadmin_pass: {{data.django_settings.MAILMAN_REST_API_PASS}}\n"""
                lines.append(i)
            if lines:
              with open('deployment/mailman.cfg', 'w') as wfic:
                wfic.write('\n'.join(lines))
            EOF
            #python << EOF
            #from __future__ import print_function
            #lines = []
            #with open('deployment/mailman.cfg') as fic:
            #  content = fic.read()
            #  for i in content.splitlines():
            #    if i.startswith('url: postgre'):
            #      i = """url: postgres://{{db.USER}}:{{db.PASSWORD}}@{{db.HOST}}:{{db.PORT}}/{{db.NAME}}"""
            #    lines.append(i)
            #if lines:
            #  with open('deployment/mailman.cfg', 'w') as wfic:
            #    wfic.write('\n'.join(lines))
            #EOF
    - mode: 700
    - user: {{cfg.user}}
    - watch:
      - buildout: {{cfg.name}}-buildout-project
  cmd.run:
    - name: {{data.app_root}}/../cfg-post.sh
    - user: {{cfg.user}}
    - watch:
      - file: {{cfg.name}}-post


{{cfg.name}}-service:
  file.managed:
    - source: {{data.app_root}}/deployment/mailman3.service
    - name: /etc/systemd/system/mailman3.service
    - mode: 640
    - user: root
    - group: root
    - watch:
      - file: {{cfg.name}}-post
  cmd.watch:
    - name: if which systemctl >/dev/null 2>&1;then systemctl daemon-reload;fi
    - watch:
      - file: {{cfg.name}}-service


{{cfg.name}}-logrotate:
  file.managed:
    - source: {{data.app_root}}/deployment/mailman3.logrotate.conf
    - name: /etc/logrotate.d/mailman3
    - mode: 640
    - user: root
    - group: root
    - watch:
      - file: {{cfg.name}}-post


{% for state in ['buildout: {0}-buildout-project', 'cmd: {0}-post'] %}
{{cfg.name}}-restore-deployment{{loop.index}}:
  cmd.run:
    - name: rsync -aA {{data.app_root}}/deployment.sav/ {{data.app_root}}/deployment/ && exit 1
    - onlyif: test -e {{data.app_root}}/deployment.sav/
    - onfail:
      - {{state.format(cfg.name)}}
{% endfor %}


