{% set cfg = opts.ms_project %}
{% set data = cfg.data %}

include:
  - makina-states.services.mail.postfix.hooks
  {% if data.postfix %}
  - makina-states.services.mail.postfix
  {% endif %}


