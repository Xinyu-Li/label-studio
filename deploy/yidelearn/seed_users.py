import csv
import os
import sys
from pathlib import Path

LS_PATH = os.environ.get(
    'LABEL_STUDIO_PACKAGE_PATH',
    '/opt/label-studio/venv/lib/python3.12/site-packages/label_studio',
)
if LS_PATH not in sys.path:
    sys.path.insert(0, LS_PATH)

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'label_studio.core.settings.label_studio')
os.environ.setdefault('LABEL_STUDIO_BASE_DATA_DIR', '/opt/label-studio/data')
os.environ.setdefault('HOST', 'https://yidelearn.com/label-studio')
os.environ.setdefault('LABEL_STUDIO_HOST', 'https://yidelearn.com/label-studio')
os.environ.setdefault('LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK', 'true')
os.environ.setdefault('DISABLE_SIGNUP_WITHOUT_LINK', 'true')
os.environ.setdefault('USE_USERNAME_FOR_LOGIN', 'true')
os.environ.setdefault('DJANGO_DB', 'sqlite')

import django

django.setup()

from django.core.management import call_command
from organizations.models import Organization
from rest_framework.authtoken.models import Token
from users.models import User


users_file = Path(os.environ.get('LABEL_STUDIO_USERS_FILE', '/opt/label-studio/config/users.tsv'))

call_command('migrate', interactive=False, verbosity=0)

rows = []
with users_file.open('r', encoding='utf-8', newline='') as handle:
    reader = csv.DictReader(handle, delimiter='\t')
    for row in reader:
        username = (row.get('username') or '').strip()
        password = (row.get('password') or '').strip()
        if not username or username.startswith('#'):
            continue
        if not password:
            raise SystemExit(f'Missing password for {username}')
        rows.append((username, password))

if not rows:
    raise SystemExit(f'No users found in {users_file}')

org = Organization.objects.first()
created = 0
updated = 0

for idx, (username, password) in enumerate(rows):
    user, was_created = User.objects.get_or_create(email=username, defaults={'username': username})
    if was_created:
        created += 1
    else:
        updated += 1

    user.username = username
    user.is_active = True
    if idx == 0:
        user.is_staff = True
        user.is_superuser = True
    user.set_password(password)
    user.save()
    Token.objects.get_or_create(user=user)

    if org is None:
        org = Organization.create_organization(created_by=user, title='Label Studio')
    if not org.has_user(user):
        org.add_user(user)
    user.active_organization = org
    user.save(update_fields=['active_organization'])

print(f'Synced {len(rows)} users from {users_file} (created={created}, updated={updated})')
print(f'Organization: {org.title}, id={org.id}')
print('First account is staff/superuser for maintenance; all accounts are active organization members.')
