import os
import zipfile
import tarfile

def add_file_to_zip(zf, filepath):
    if not os.path.exists(filepath):
        return
    zinfo = zipfile.ZipInfo.from_file(filepath, arcname=filepath)
    if filepath in ['project2', 'project2_bonus']:
        zinfo.external_attr = 0o755 << 16
    zf.writestr(zinfo, open(filepath, 'rb').read())

def add_file_to_tar(tf, filepath):
    if not os.path.exists(filepath):
        return
    def filter_func(tarinfo):
        if tarinfo.name in ['project2', 'project2_bonus']:
            tarinfo.mode = 0o755
        return tarinfo
    tf.add(filepath, arcname=filepath, filter=filter_func)

def create_archives():
    # 1. project2 package
    p2_files = ['project2.erl', 'project2', 'project2.bat', 'README', 'README.md']
    
    # zip
    with zipfile.ZipFile('project2.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
        for f in p2_files:
            add_file_to_zip(zf, f)
    print("Created project2.zip")

    # tgz
    with tarfile.open('project2.tgz', 'w:gz') as tf:
        for f in p2_files:
            add_file_to_tar(tf, f)
    print("Created project2.tgz")

    # 2. project2-bonus package
    p2_bonus_files = ['project2_bonus.erl', 'project2_bonus', 'project2_bonus.bat', 'README', 'README.md']
    
    # zip
    with zipfile.ZipFile('project2-bonus.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
        for f in p2_bonus_files:
            add_file_to_zip(zf, f)
    print("Created project2-bonus.zip")

    # tgz
    with tarfile.open('project2-bonus.tgz', 'w:gz') as tf:
        for f in p2_bonus_files:
            add_file_to_tar(tf, f)
    print("Created project2-bonus.tgz")

if __name__ == '__main__':
    create_archives()
