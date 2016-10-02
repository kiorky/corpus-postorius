{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set ds = data.django_settings %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}

{% macro set_env() %}
    - env:
      - DJANGO_SETTINGS_MODULE: "{{data.DJANGO_SETTINGS_MODULE}}"
{% endmacro %}

include:
  - makina-projects.{{cfg.name}}.include.configs

# backward compatible ID !

{{cfg.name}}-stop-all:
  cmd.run:
    - name: |
            if which nginx >/dev/null 2>&1;then
                if [ ! -d /etc/nginx/disabled ];then mkdir /etc/nginx/disabled;fi
                mv -f /etc/nginx/sites-enabled/corpus-{{cfg.name}}.conf /etc/nginx/disabled/corpus-{{cfg.name}}.conf
                service nginx restart || /bin/true;
            fi
            # onlyif circus running
            if ps afux|grep "bin/circusd"|grep -v grep|grep -q circusd;then
              # circusctl can make long to answer, try 3times
              if which circusctl >/dev/null 2>&1;then
                  circusctl stop {{cfg.name}}-django ||\
                  ( sleep 1 && circusctl stop {{cfg.name}}-django ) ||\
                  ( sleep 1 && circusctl stop {{cfg.name}}-django )
              fi
            fi
    - watch_in:
      - file: {{cfg.name}}-config
      - cmd: {{cfg.name}}-start-all

{{cfg.name}}-config:
  file.exists:
    - name: "{{data.configs['settings_local.py']['target']}}"
    - watch:
      - mc_proxy: "{{cfg.name}}-configs-post"

postupdate-{{cfg.name}}:
  cmd.run:
    - name: |
            . ../venv/bin/activate
            ./bin/mailman-post-update
    {{set_env()}}
    - use_vt: true
    - cwd: {{data.app_root}}
    - user: {{cfg.user}}
    - watch:
      - mc_proxy: {{cfg.name}}-configs-post
    - watch_in:
      - cmd: {{cfg.name}}-start-all

{% if data.get('create_admins', True) %}
{% for dadmins in data.admins %}
{% for admin, udata in dadmins.items() %}
{% set f = data.app_root + '/salt_' + admin + '_check.py' %}
user-{{cfg.name}}-{{admin}}:
  file.managed:
    - name: "{{f}}"
    - contents: |
                #!{{data.app_root}}/bin/python
                import os
                try:
                    import django;django.setup()
                except Exception:
                    pass
                from {{ds.USER_MODULE}} import {{ds.USER_CLASS}} as User
                User.objects.filter(username='{{admin}}').all()[0]
                if os.path.isfile("{{f}}"):
                    os.unlink("{{f}}")
    - mode: 700
    - template: jinja
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - source: ""
    - cwd: {{data.app_root}}
    - user: {{cfg.user}}
    - watch:
      - mc_proxy: {{cfg.name}}-configs-post
      - cmd: postupdate-{{cfg.name}}
  cmd.run:
    - name: bin/mailman-web-django-admin createsuperuser --username="{{admin}}" --email="{{udata.mail}}" --noinput
    - unless: "{{f}}"
    {{set_env()}}
    - cwd: {{data.app_root}}
    - user: {{cfg.user}}
    - watch:
      - mc_proxy: {{cfg.name}}-configs-post
      - cmd: postupdate-{{cfg.name}}
      - file: user-{{cfg.name}}-{{admin}}
    - watch_in:
      - cmd: {{cfg.name}}-start-all

{% set f = data.app_root + '/salt_' + admin + '_password.py' %}
superuser-{{cfg.name}}-{{admin}}:
  file.managed:
    - contents: |
                #!{{data.app_root}}/bin/python
                import os
                try:
                    import django;django.setup()
                except Exception:
                    pass
                from {{ds.USER_MODULE}} import {{ds.USER_CLASS}} as User
                user=User.objects.filter(username='{{admin}}').all()[0]
                user.set_password('{{udata.password}}')
                user.email = '{{udata.mail}}'
                user.save()
                if os.path.isfile("{{f}}"):
                    os.unlink("{{f}}")
    - template: jinja
    - mode: 700
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - name: "{{f}}"
    - watch:
      - mc_proxy: {{cfg.name}}-configs-post
      - cmd: postupdate-{{cfg.name}}
  cmd.run:
    {{set_env()}}
    - name: {{f}}
    - cwd: {{data.app_root}}
    - user: {{cfg.user}}
    - watch:
      - cmd: user-{{cfg.name}}-{{admin}}
      - file: superuser-{{cfg.name}}-{{admin}}
    - watch_in:
      - cmd: {{cfg.name}}-start-all
{%endfor %}
{%endfor %}
{%endif %}

{{cfg.name}}-start-all:
  cmd.run:
    - name: |
            if which nginx >/dev/null 2>&1;then
                if [ ! -d /etc/nginx/disabled ];then mkdir /etc/nginx/disabled;fi
                mv -f /etc/nginx/disabled/corpus-{{cfg.name}}.conf /etc/nginx/sites-enabled/corpus-{{cfg.name}}.conf &&\
                service nginx restart || /bin/true;
            fi
            # start circus if not working  yet
            if ! ps afux|grep "bin/circusd"|grep -v grep|grep -q circusd;then
              service circusd start
            fi
            # circusctl can make long to answer, try 3times
            if which circusctl >/dev/null 2>&1;then
                circusctl start {{cfg.name}}-django ||\
                ( sleep 1 && circusctl start {{cfg.name}}-django ) ||\
                ( sleep 1 && circusctl start {{cfg.name}}-django )
            fi

{{cfg.name}}-crons:
  file.managed:
    - name: /etc/cron.d/{{cfg.name}}crons
    - mode: 600
    - contents: |
        @hourly            su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs hourly         >/dev/null 2>&1"
        @daily             su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs daily          >/dev/null 2>&1"
        @weekly            su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs weekly         >/dev/null 2>&1"
        @monthly           su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs monthly        >/dev/null 2>&1"
        @yearly            su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs yearly         >/dev/null 2>&1"
        0,15,30,45 * * * * su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs quarter_hourly >/dev/null 2>&1"
        * * * * *          su -l {{cfg.user}} -c "{{data.app_root}}/bin/mailman-web-django-admin runjobs minutely       >/dev/null 2>&1"
    - watch:
      - cmd: {{cfg.name}}-start-all



