rm -f trainer.tar trainer.tar.gz
tar cvf trainer.tar package
gzip trainer.tar
gsutil cp trainer.tar.gz $GCS_PACKAGE_URI/cheese-app-trainer.tar.gz