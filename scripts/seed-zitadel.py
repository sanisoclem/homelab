#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import re
import ssl
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field

CUSTOMER_ORG = 'hempire-customers'
INTERNAL_ORG = 'hempire-internal'
CUSTOMER_PROJECT = 'Customer Facing APIs'
INTERNAL_PROJECT = 'Internal APIs'
BFF_APP = 'Application BFF'
ADMIN_APP = 'Admin Portal'

TF_VARS = {
    'crm-api': (None, 'TF_VAR_crm_zitadel_client_secret'),
    'bank-api': ('TF_VAR_bank_client_id', 'TF_VAR_bank_client_secret'),
    'bridge-api': ('TF_VAR_bridge_client_id', 'TF_VAR_bridge_client_secret'),
    'budget-api': ('TF_VAR_budget_client_id', 'TF_VAR_budget_client_secret'),
}

@dataclass(frozen=True)
class Role:
    key: str
    display_name: str
    group: str

@dataclass(frozen=True)
class OidcApp:
    name: str
    redirect_uris: tuple
    post_logout_redirect_uris: tuple
    dev_mode: bool
    access_token_role_assertion: bool
    id_token_userinfo_assertion: bool

@dataclass(frozen=True)
class Project:
    name: str
    role_assertion: bool
    role_check: bool
    project_check: bool
    roles: tuple
    apps: tuple

@dataclass(frozen=True)
class ServiceUser:
    user_name: str
    with_secret: bool

@dataclass(frozen=True)
class Org:
    name: str
    projects: tuple
    service_users: tuple

@dataclass(frozen=True)
class ProjectRoleGrant:
    org: str
    user_name: str
    project: str
    roles: tuple

@dataclass(frozen=True)
class OrgMembership:
    org: str
    user_org: str
    user_name: str
    roles: tuple

@dataclass(frozen=True)
class Instance:
    orgs: tuple
    project_role_grants: tuple
    org_memberships: tuple

def desired_instance(zone, envs):
    return Instance(
        orgs=(
            Org(
                name=CUSTOMER_ORG,
                projects=(
                    Project(
                        name=CUSTOMER_PROJECT,
                        role_assertion=False,
                        role_check=False,
                        project_check=False,
                        roles=(),
                        apps=(
                            OidcApp(
                                name=BFF_APP,
                                redirect_uris=login_callbacks('app', zone, envs),
                                post_logout_redirect_uris=post_logout_urls('app', zone, envs),
                                dev_mode=False,
                                access_token_role_assertion=False,
                                id_token_userinfo_assertion=False,
                            ),
                        ),
                    ),
                ),
                service_users=(),
            ),
            Org(
                name=INTERNAL_ORG,
                projects=(
                    Project(
                        name=INTERNAL_PROJECT,
                        role_assertion=True,
                        role_check=True,
                        project_check=True,
                        roles=(
                            Role('crm-user', 'CRM User', 'default'),
                            Role('bank-user', 'Bank User', 'default'),
                            Role('ledger-user', 'Ledger User', 'default'),
                        ),
                        apps=(
                            OidcApp(
                                name=ADMIN_APP,
                                redirect_uris=login_callbacks('admin', zone, envs),
                                post_logout_redirect_uris=(),
                                dev_mode=True,
                                access_token_role_assertion=True,
                                id_token_userinfo_assertion=True,
                            ),
                        ),
                    ),
                ),
                service_users=(
                    ServiceUser('crm-api', with_secret=True),
                    ServiceUser('bank-api', with_secret=True),
                    ServiceUser('bridge-api', with_secret=True),
                    ServiceUser('budget-api', with_secret=True),
                    ServiceUser('ledger-api', with_secret=False),
                ),
            ),
        ),
        project_role_grants=(
            ProjectRoleGrant(INTERNAL_ORG, 'bank-api', INTERNAL_PROJECT, ('ledger-user',)),
            ProjectRoleGrant(INTERNAL_ORG, 'bridge-api', INTERNAL_PROJECT, ('ledger-user',)),
            ProjectRoleGrant(INTERNAL_ORG, 'budget-api', INTERNAL_PROJECT, ('ledger-user',)),
        ),
        org_memberships=(
            OrgMembership(CUSTOMER_ORG, INTERNAL_ORG, 'crm-api', ('ORG_OWNER', 'ORG_USER_MANAGER')),
            OrgMembership(INTERNAL_ORG, INTERNAL_ORG, 'crm-api', ('ORG_OWNER', 'ORG_USER_SELF_MANAGER')),
        ),
    )

def login_callbacks(host_prefix, zone, envs):
    return tuple(f'https://{host_prefix}-{env}.{zone}/login/callback' for env in envs)

def post_logout_urls(host_prefix, zone, envs):
    return tuple(f'https://{host_prefix}-{env}.{zone}' for env in envs)

class SeedError(Exception):
    pass

class Zitadel:
    def __init__(self, base_url, token, host=None, verify=True):
        self._base_url = base_url.rstrip('/')
        self._token = token
        self._host = host
        self._context = ssl.create_default_context()
        if not verify:
            self._context.check_hostname = False
            self._context.verify_mode = ssl.CERT_NONE

    def call(self, method, path, org=None, body=None):
        request = urllib.request.Request(
            f'{self._base_url}{path}',
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers=self._headers(org),
        )
        try:
            with urllib.request.urlopen(request, timeout=30, context=self._context) as response:
                return json.load(response)
        except urllib.error.HTTPError as failure:
            raise SeedError(f'{method} {path} -> {failure.code} {failure.read().decode()}') from failure

    def search(self, path, org=None):
        return self.call('POST', path, org=org, body={'query': {'limit': 500}}).get('result') or []

    def _headers(self, org):
        headers = {'Authorization': f'Bearer {self._token}', 'Content-Type': 'application/json'}
        if self._host is not None:
            headers['Host'] = self._host
        if org is not None:
            headers['x-zitadel-orgid'] = org
        return headers

@dataclass
class Outcome:
    created: list = field(default_factory=list)
    updated: list = field(default_factory=list)
    unchanged: list = field(default_factory=list)
    secrets: dict = field(default_factory=dict)

    def record_created(self, what):
        self.created.append(what)
        print(f'  created  {what}')

    def record_updated(self, what):
        self.updated.append(what)
        print(f'  updated  {what}')

    def record_unchanged(self, what):
        self.unchanged.append(what)
        print(f'  exists   {what}')

def seed(api, instance, outcome, env_vars):
    for org in instance.orgs:
        seed_org(api, org, outcome, env_vars)
    for grant in instance.project_role_grants:
        seed_project_role_grant(api, grant, outcome)
    for membership in instance.org_memberships:
        seed_org_membership(api, membership, outcome)

def seed_org(api, org, outcome, env_vars):
    org_id = ensure_org(api, org.name, outcome)
    for project in org.projects:
        seed_project(api, org_id, project, outcome)
    for user in org.service_users:
        seed_service_user(api, org_id, user, outcome, env_vars)

def seed_project(api, org_id, project, outcome):
    project_id = ensure_project(api, org_id, project, outcome)
    for role in project.roles:
        ensure_role(api, org_id, project_id, role, outcome)
    for app in project.apps:
        ensure_oidc_app(api, org_id, project_id, app, outcome)

def seed_service_user(api, org_id, user, outcome, env_vars):
    users = api.search('/management/v1/users/_search', org=org_id)
    existing = find_by(users, 'userName', user.user_name)
    if existing is None:
        user_id = create_service_user(api, org_id, user, outcome)
    else:
        user_id = existing['id']
        outcome.record_unchanged(f'service user {user.user_name}')
    if needs_client_secret(user, existing, env_vars):
        generate_client_secret(api, org_id, user_id, user.user_name, outcome)

def create_service_user(api, org_id, user, outcome):
    created = api.call('POST', '/management/v1/users/machine', org=org_id, body={
        'userName': user.user_name,
        'name': user.user_name,
        'accessTokenType': 'ACCESS_TOKEN_TYPE_JWT',
    })
    outcome.record_created(f'service user {user.user_name}')
    return created['userId']

def needs_client_secret(user, existing, env_vars):
    if not user.with_secret:
        return False
    return existing is None or not env_holds_secret(env_vars, user.user_name)

def env_holds_secret(env_vars, user_name):
    return all(env_vars.get(variable) for variable in TF_VARS[user_name] if variable)

def generate_client_secret(api, org_id, user_id, user_name, outcome):
    generated = api.call('PUT', f'/management/v1/users/{user_id}/secret', org=org_id, body={})
    outcome.secrets[user_name] = (generated['clientId'], generated['clientSecret'])
    outcome.record_created(f'client secret for {user_name}')

def seed_project_role_grant(api, grant, outcome):
    org_id = org_id_by_name(api, grant.org)
    users = api.search('/management/v1/users/_search', org=org_id)
    projects = api.search('/management/v1/projects/_search', org=org_id)
    user_id = require(find_by(users, 'userName', grant.user_name), f'service user {grant.user_name}')['id']
    project_id = require(find_by(projects, 'name', grant.project), f'project {grant.project}')['id']
    granted = api.search('/management/v1/users/grants/_search', org=org_id)
    existing = next((g for g in granted if g.get('userId') == user_id and g.get('projectId') == project_id), None)
    if existing is None:
        api.call('POST', f'/management/v1/users/{user_id}/grants', org=org_id, body={
            'projectId': project_id,
            'roleKeys': list(grant.roles),
        })
        outcome.record_created(f'grant {grant.user_name} -> {grant.project} {list(grant.roles)}')
        return
    widened = widened_roles(existing.get('roleKeys'), grant.roles)
    if widened is None:
        outcome.record_unchanged(f'grant {grant.user_name} -> {grant.project} {list(grant.roles)}')
        return
    api.call('PUT', f'/management/v1/users/{user_id}/grants/{existing["id"]}', org=org_id,
             body={'roleKeys': widened})
    outcome.record_updated(f'grant {grant.user_name} -> {grant.project} {widened}')

def seed_org_membership(api, membership, outcome):
    org_id = org_id_by_name(api, membership.org)
    user_org_id = org_id_by_name(api, membership.user_org)
    users = api.search('/management/v1/users/_search', org=user_org_id)
    user_id = require(find_by(users, 'userName', membership.user_name), f'service user {membership.user_name}')['id']
    members = api.search('/management/v1/orgs/me/members/_search', org=org_id)
    existing = find_by(members, 'userId', user_id)
    if existing is None:
        api.call('POST', '/management/v1/orgs/me/members', org=org_id, body={
            'userId': user_id,
            'roles': list(membership.roles),
        })
        outcome.record_created(f'org member {membership.user_name} in {membership.org} {list(membership.roles)}')
        return
    widened = widened_roles(existing.get('roles'), membership.roles)
    if widened is None:
        outcome.record_unchanged(f'org member {membership.user_name} in {membership.org}')
        return
    api.call('PUT', f'/management/v1/orgs/me/members/{user_id}', org=org_id, body={'roles': widened})
    outcome.record_updated(f'org member {membership.user_name} in {membership.org} {widened}')

def ensure_org(api, name, outcome):
    existing = find_by(api.search('/admin/v1/orgs/_search'), 'name', name)
    if existing:
        outcome.record_unchanged(f'org {name}')
        return existing['id']
    created = api.call('POST', '/management/v1/orgs', body={'name': name})
    outcome.record_created(f'org {name}')
    return created['id']

def ensure_project(api, org_id, project, outcome):
    projects = api.search('/management/v1/projects/_search', org=org_id)
    existing = find_by(projects, 'name', project.name)
    if existing:
        outcome.record_unchanged(f'project {project.name}')
        return existing['id']
    created = api.call('POST', '/management/v1/projects', org=org_id, body={
        'name': project.name,
        'projectRoleAssertion': project.role_assertion,
        'projectRoleCheck': project.role_check,
        'hasProjectCheck': project.project_check,
        'privateLabelingSetting': 'PRIVATE_LABELING_SETTING_UNSPECIFIED',
    })
    outcome.record_created(f'project {project.name}')
    return created['id']

def ensure_role(api, org_id, project_id, role, outcome):
    roles = api.search(f'/management/v1/projects/{project_id}/roles/_search', org=org_id)
    if find_by(roles, 'key', role.key):
        outcome.record_unchanged(f'role {role.key}')
        return
    api.call('POST', f'/management/v1/projects/{project_id}/roles', org=org_id, body={
        'projectId': project_id,
        'roleKey': role.key,
        'displayName': role.display_name,
        'group': role.group,
    })
    outcome.record_created(f'role {role.key}')

def ensure_oidc_app(api, org_id, project_id, app, outcome):
    apps = api.search(f'/management/v1/projects/{project_id}/apps/_search', org=org_id)
    if find_by(apps, 'name', app.name):
        outcome.record_unchanged(f'app {app.name}')
        return
    created = api.call('POST', f'/management/v1/projects/{project_id}/apps/oidc', org=org_id, body={
        'name': app.name,
        'redirectUris': list(app.redirect_uris),
        'responseTypes': ['OIDC_RESPONSE_TYPE_CODE'],
        'grantTypes': ['OIDC_GRANT_TYPE_AUTHORIZATION_CODE', 'OIDC_GRANT_TYPE_REFRESH_TOKEN'],
        'appType': 'OIDC_APP_TYPE_WEB',
        'authMethodType': 'OIDC_AUTH_METHOD_TYPE_NONE',
        'postLogoutRedirectUris': list(app.post_logout_redirect_uris),
        'version': 'OIDC_VERSION_1_0',
        'devMode': app.dev_mode,
        'accessTokenType': 'OIDC_TOKEN_TYPE_JWT',
        'accessTokenRoleAssertion': app.access_token_role_assertion,
        'idTokenRoleAssertion': False,
        'idTokenUserinfoAssertion': app.id_token_userinfo_assertion,
        'clockSkew': '0s',
        'additionalOrigins': [],
        'skipNativeAppSuccessPage': False,
    })
    outcome.record_created(f'app {app.name}')
    warn_if_non_compliant(app.name, created)

def warn_if_non_compliant(app_name, created):
    if not created.get('noneCompliant'):
        return
    problems = ', '.join(p.get('localizedMessage', p.get('key', '')) for p in created.get('complianceProblems') or [])
    print(f'  WARNING  {app_name} was created but Zitadel reports it non-compliant: {problems}')

def org_by_name(api, name):
    org = find_by(api.search('/admin/v1/orgs/_search'), 'name', name)
    if org is None:
        raise SeedError(f'org {name} not found')
    return org

def org_id_by_name(api, name):
    return org_by_name(api, name)['id']

def primary_domain(org):
    domain = org.get('primaryDomain')
    if not domain:
        raise SeedError(f"org {org['name']} has no primary domain")
    return domain

def find_by(items, key, value):
    return next((item for item in items if item.get(key) == value), None)

def require(item, description):
    if item is None:
        raise SeedError(f'{description} not found')
    return item

def widened_roles(held, wanted):
    held = set(held or ())
    return None if set(wanted) <= held else sorted(held | set(wanted))

def seeded_identifiers(api):
    customer_org = org_by_name(api, CUSTOMER_ORG)
    internal_org = org_by_name(api, INTERNAL_ORG)
    customer_org_id = customer_org['id']
    internal_org_id = internal_org['id']
    customer_projects = api.search('/management/v1/projects/_search', org=customer_org_id)
    internal_projects = api.search('/management/v1/projects/_search', org=internal_org_id)
    customer_project = require(find_by(customer_projects, 'name', CUSTOMER_PROJECT), CUSTOMER_PROJECT)
    internal_project = require(find_by(internal_projects, 'name', INTERNAL_PROJECT), INTERNAL_PROJECT)
    return {
        'CUSTOMER_AUDIENCE': customer_project['id'],
        'INTERNAL_AUDIENCE': internal_project['id'],
        'BACKEND_AUTH_CUSTOMER_ORG_ID': customer_org_id,
        'CUSTOMER_ORG_DOMAIN': primary_domain(customer_org),
        'INTERNAL_ORG_ID': internal_org_id,
        'BFF_CLIENT_ID': oidc_client_id(api, customer_org_id, customer_project['id'], BFF_APP),
        'ADMIN_CLIENT_ID': oidc_client_id(api, internal_org_id, internal_project['id'], ADMIN_APP),
    }

def oidc_client_id(api, org_id, project_id, app_name):
    apps = api.search(f'/management/v1/projects/{project_id}/apps/_search', org=org_id)
    return require(find_by(apps, 'name', app_name), f'app {app_name}')['oidcConfig']['clientId']

def auth_config_path(gitops_dir):
    return pathlib.Path(gitops_dir, 'config', 'cluster-config.yaml')

def cluster_dns_zone(gitops_dir):
    config = auth_config_path(gitops_dir)
    found = re.search(r'^\s+DNS_ZONE:\s*(\S+)\s*$', config.read_text(), re.MULTILINE)
    if found is None:
        raise SeedError(f'{config} has no DNS_ZONE')
    return found.group(1)

def environment_names(gitops_dir):
    envs = pathlib.Path(gitops_dir, 'envs')
    names = sorted(child.name for child in envs.iterdir() if child.is_dir())
    if not names:
        raise SeedError(f'{envs} holds no environments')
    return names

def patch_yaml_values(path, updates):
    content = path.read_text()
    missing = [key for key in updates if not re.search(rf'^\s+{re.escape(key)}:', content, re.MULTILINE)]
    if missing:
        raise SeedError(f'{path} is missing keys: {", ".join(missing)}')
    changed = []
    for key, value in updates.items():
        patched = re.sub(rf'^(\s+{re.escape(key)}:).*$', lambda m, v=value: f'{m.group(1)} "{v}"',
                         content, flags=re.MULTILINE)
        if patched != content:
            changed.append(key)
        content = patched
    path.write_text(content)
    return changed

def patch_env_file(path, updates):
    lines = path.read_text().splitlines(keepends=True) if path.exists() else []
    remaining = dict(updates)
    for index, line in enumerate(lines):
        key = line.split('=', 1)[0].strip()
        if key in remaining:
            lines[index] = f'{key}={remaining.pop(key)}\n'
    trailer = [f'{key}={value}\n' for key, value in remaining.items()]
    if trailer and lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    path.write_text(''.join(lines + trailer))

def read_env_file(path):
    if not path.exists():
        return {}
    pairs = (line.split('=', 1) for line in path.read_text().splitlines() if '=' in line)
    return {key.strip(): value.strip() for key, value in pairs}

def secret_env_updates(secrets):
    updates = {}
    for user_name, (client_id, client_secret) in secrets.items():
        id_var, secret_var = TF_VARS[user_name]
        if id_var:
            updates[id_var] = client_id
        updates[secret_var] = client_secret
    return updates

def report(api, outcome, gitops_dir, env_file, token):
    print(f'\n{len(outcome.created)} created, {len(outcome.updated)} updated, '
          f'{len(outcome.unchanged)} already present.')

    config = auth_config_path(gitops_dir)
    changed = patch_yaml_values(config, seeded_identifiers(api))
    relative = config.relative_to(pathlib.Path(gitops_dir).parent)
    print(f'\n{relative}: ' + (f'updated {", ".join(changed)}' if changed else 'already current'))

    secrets = secret_env_updates(outcome.secrets)
    patch_env_file(env_file, {**secrets, 'ZITADEL_PAT': token})
    if not secrets:
        print(f'{env_file}: cached ZITADEL_PAT')
        print('seed: no secret changes')
        return
    print(f'{env_file}: wrote {", ".join(sorted(secrets))} and cached ZITADEL_PAT')
    print('seed: secrets updated')

def read_token(token_file):
    from_env = os.environ.get('ZITADEL_TOKEN')
    if from_env:
        return from_env.strip()
    if token_file:
        return pathlib.Path(os.path.expanduser(token_file)).read_text().strip()
    raise SeedError('set ZITADEL_TOKEN or pass --token-file')

def parse_args(argv):
    parser = argparse.ArgumentParser(
        description='Seed this cluster\'s Zitadel with the hempire orgs, projects, apps, service '
                    'users and permissions, then write the identifiers it generated into the '
                    'gitops config and the client secrets into this repo\'s .env. Creates what is '
                    'missing and grants what an existing object lacks, never rotating a client '
                    'secret the .env already holds.')
    parser.add_argument('--url', required=True, help='base URL to reach Zitadel on')
    parser.add_argument('--insecure', action='store_true', help='skip TLS verification (port-forward)')
    parser.add_argument('--gitops-dir', required=True, help='path to the app repo checkout')
    parser.add_argument('--env-file', required=True, help='.env file to write client secrets into')
    parser.add_argument('--token-file', help='file holding a PAT for a service user with IAM_OWNER')
    return parser.parse_args(argv)

def main(argv):
    args = parse_args(argv)
    zone = cluster_dns_zone(args.gitops_dir)
    envs = environment_names(args.gitops_dir)
    token = read_token(args.token_file)
    env_file = pathlib.Path(args.env_file)
    api = Zitadel(args.url, token, host=f'a.{zone}', verify=not args.insecure)
    outcome = Outcome()
    print(f'Seeding a.{zone} for environments {", ".join(envs)}')
    seed(api, desired_instance(zone, envs), outcome, read_env_file(env_file))
    report(api, outcome, args.gitops_dir, env_file, token)
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except SeedError as failure:
        sys.exit(f'error: {failure}')
