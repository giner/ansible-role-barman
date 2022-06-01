[![Run tests][tests-badge]][tests-link]

# Ansible Role: Barman

Installs and configures Barman on Linux with optional:
- regular backup (running by cron)
- wals and snapshots uploading to S3 (running by cron)
- metrics collection (by telegraf)

This role is aimed to be as unopinionated as possible, i.e. all configuration parameters are passed through directly to barman configs.

## Requirements

* Ubuntu

## Installation

Install via [Ansible Galaxy][galaxy-link]:

```
ansible-galaxy collection install giner.barman
```

Or include this role in your `requirements.yml` file:

```
roles:
  - name: giner.barman
```

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

Barman requested state. Override with `absent` to uninstall Barman. Data won't be removed.

    barman_state: started

Barman package requested state. Override with `latest` to upgrade Barman.

    barman_package_state: present

Barman's global config overrides (key/value).

    barman_config: {}

PostgreSQL servers to backup.

    barman_pg_servers: []    # The keys are: name, params, pgpass and cron. See an example below.

Configure telegraf to collect Barman metrics.

    barman_telegraf_enabled: false

Metrics collection interval.

    barman_telegraf_interval: 1m

## Dependencies

None.

## Example Playbook

    # Configure users and their privileges on PostgreSQL db server
    # http://docs.pgbarman.org/release/2.12/#postgresql-connection
    - hosts: postgresqls
      vars:
        barman_user: barman
        barman_pass: BARMANPASS_CHANGEME
        barman_streaming_user: streaming_barman
        barman_streaming_pass: STREAMINGPASS_CHANGEME
      tasks:
      - name: Add PostgreSQL user barman_user
        postgresql_user:
          user: "{{ barman_user }}"
          password: "{{ barman_pass }}"
          role_attr_flags: replication
          groups: [pg_read_all_settings, pg_read_all_stats]
      - name: Add PostgreSQL user barman_streaming_user
        postgresql_user:
          user: "{{ barman_streaming_user }}"
          password: "{{ barman_streaming_pass }}"
          role_attr_flags: replication
      - name: GRANT EXECUTE PRIVILEGES ON FUNCTION pg_XXX TO barman_user
        postgresql_privs:
          db: postgres
          privs: EXECUTE
          type: function
          obj: pg_start_backup(text:boolean:boolean),pg_stop_backup(),pg_stop_backup(boolean:boolean),pg_switch_wal(),pg_create_restore_point(text)
          schema: pg_catalog
          roles: "{{ barman_user }}"

    # Setup and configure Barman
    - hosts: barmans
      vars:
        barman_name: mypgserver
        barman_pg_hosts: 10.10.10.10
        barman_pg_ports: 5432
        barman_user: barman
        barman_pass: BARMANPASS_CHANGEME
        barman_streaming_user: streaming_barman
        barman_streaming_pass: STREAMINGPASS_CHANGEME
        barman_pg_servers:
        - name: "{{ barman_name }}"
          params:
          - description: "PostgreSQL Database (Streaming-Only)"
          - conninfo: 'host={{ barman_pg_hosts }} port={{ barman_pg_ports }} user={{ barman_user }} dbname=postgres'
          - streaming_conninfo: 'host={{ barman_pg_hosts }} port={{ barman_pg_ports }} user={{ barman_streaming_user }}'
          - backup_method: "postgres"
          - streaming_archiver: "on"
          - slot_name: "barman"
          - create_slot: "auto"
          - retention_policy: "recovery window of 31 days"
          pgpass:
          - "*:*:postgres:{{ barman_user }}:{{ barman_pass }}"
          - "*:*:replication:{{ barman_streaming_user }}:{{ barman_streaming_pass }}"
          backup_schedule:
            cron:
              hour: 21
              minute: 5
            s3_sync:
              src: "{{ barman_config['barman_home'] | default('/var/lib/barman') }}/{{ barman_name }}"
              dst: "s3://db-backup"
              base_cron:
                hour: 22
                minute: 5
              wals_cron:
                minute: 10
            custom:
              job: "barman delete '{{ barman_name }}' oldest"
              cron:
                hour: 23
                minute: 15
      roles:
      - giner.barman

## Development

Install test dependencies:

    python3 -m pip install ansible -Ur requirements-molecule.txt

Run all tests (requires docker to be installed):

    molecule test --all

## License

Apache 2.0

## Authors

This role was created in 2021 by [Stanislav German-Evtushenko](https://github.com/giner)

[galaxy-link]:   https://galaxy.ansible.com/giner/barman
[tests-badge]:   https://github.com/giner/ansible-role-barman/actions/workflows/test.yml/badge.svg
[tests-link]:    https://github.com/giner/ansible-role-barman/actions/workflows/test.yml
