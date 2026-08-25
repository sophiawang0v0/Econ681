import os
import zipfile
from pathlib import Path
import shutil

zip_folder  = 'raw_data'
data_folder = 'extracted_data'
tag_folder = 'data_tags'

# clean folder contents
for item in Path(data_folder).iterdir():
    if item.is_file() or item.is_symlink():
        item.unlink()
    elif item.is_dir():
        shutil.rmtree(item)
for item in Path(tag_folder).iterdir():
    if item.is_file() or item.is_symlink():
        item.unlink()
    elif item.is_dir():
        shutil.rmtree(item)

# Extract zip files
files = [f.name for f in Path(zip_folder).iterdir() if f.is_file()]
zip_file = [os.path.join(zip_folder, x) for x in files if x.endswith('.zip')]
for file in zip_file:
    with zipfile.ZipFile(file, 'r') as archive:
        for f in archive.namelist():
            if f.endswith((".cdb", ".csv")):
                archive.extract(f, data_folder)
            elif f.endswith((".NLSY79","NLSY97")):
                archive.extract(f, tag_folder)