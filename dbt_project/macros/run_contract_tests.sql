{#
  Optional on-run-end hook that shells out to datacontract-cli.
  Primary enforcement is via the Makefile `contract-test` target — this
  macro is here to show the dbt-native integration path.

  To activate, add to dbt_project.yml:
    on-run-end:
      - "{{ run_contract_tests() }}"

  Note: dbt macros can't easily shell out. This macro just logs a reminder;
  actual CLI invocation happens in the Makefile.
#}
{% macro run_contract_tests() %}
  {% do log("Reminder: run `make contract-test` to validate ODCS contracts.", info=True) %}
  {% do log("  - contracts/newsapi_raw.odcs.yaml", info=True) %}
  {% do log("  - contracts/newsapi_staging.odcs.yaml", info=True) %}
{% endmacro %}
