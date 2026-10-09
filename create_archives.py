import os
import zipfile
import tarfile

def create_archives():
    # 1. project2 package
    p2_files = ['project2.erl', 'project2', 'project2.bat', 'README', 'README.md']
    
    # zip
    with zipfile.ZipFile('project2.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
        for f in p2_files:
            if os.path.exists(f):
                zf.write(f, arcname=f)
    print("Created project2.zip")

    # tgz
    with tarfile.open('project2.tgz', 'w:gz') as tf:
        for f in p2_files:
            if os.path.exists(f):
                tf.add(f, arcname=f)
    print("Created project2.tgz")

    # 2. project2-bonus package
    p2_bonus_files = ['project2_bonus.erl', 'project2_bonus', 'project2_bonus.bat', 'README', 'README.md']
    
    # zip
    with zipfile.ZipFile('project2-bonus.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
        for f in p2_bonus_files:
            if os.path.exists(f):
                zf.write(f, arcname=f)
    print("Created project2-bonus.zip")

    # tgz
    with tarfile.open('project2-bonus.tgz', 'w:gz') as tf:
        for f in p2_bonus_files:
            if os.path.exists(f):
                tf.add(f, arcname=f)
    print("Created project2-bonus.tgz")

if __name__ == '__main__':
    create_archives()

