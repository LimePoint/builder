#!/bin/bash
set -euo pipefail

aggMsg() {
    echo ""
    echo "Aggregating locally stored artifacts."
    echo "======================================"
    echo ""

}

configMsg(){
    echo ""
    echo "Configuring environment for migration."
    echo "======================================"
    echo ""
}

keyMsg() {
    echo ""
    echo "Generating S3 Object Keys."
    echo "======================================"
    echo ""
}

uploadMsg() {
    echo ""
    echo "Uploading hartfile."
    echo "======================================"
}

getHarts() {
    # Traverses the depot data path and
    # creates an array from each package
    # artifact that exists in that path

    TARGETDIR=${1}
    for f in ${TARGETDIR}/*; do
        if [[ -d "${f}" ]]; then
            getHarts "${f}"
        elif [[ "${f}" == *.hart ]]; then
            echo "Found: $f"
            artifacts+=("${f}")
        else
            echo "$f is not a hartfile, skipping."
            echo ""
        fi
    done
}

uploadHarts() {
    # Takes the artifact array generated via
    # traversing the data path and uploads to s3
    if [ ${#artifacts[@]} -eq 0 ]; then
        echo ""
        echo "No artifacts found in Artifact storage path!"
        echo "Exiting!"
        exit 1
    fi
        keyMsg
    for hart in "${artifacts[@]}"; do
        uploadMsg
        keyId=$(generateKey "${hart}")
        putArtifacts "${hart}" "${S3_BUCKET}" "${AWS_REGION}" "${keyId}"
    done
    echo ""
    echo "########################################"
    echo "${#artifacts[@]} Artifacts have been migrated to s3!"
    echo "########################################"
    echo ""
}

installDeps() {
    # We use aws-cli to handle the actual upload.
    # but we also need jq to parse the pkg info

    PDEPS=("core/aws-cli" "core/jq-static")

    configMsg

    for bin in "${!PDEPS[@]}"; do
        hab pkg install -b "${PDEPS[$bin]}"
    done
}

generateKey() {
    # Generates the s3 item key from the hartfile
    FILEIN="${1}"
    BASE="${FILEIN##*/}"

    # Get the
    MAIN=$(hab pkg info -j "${FILEIN}" | jq -r '. | .origin + "/" + .name + "/" + .version + "/" + .release ')
    ARCH="x86_64"

    SYSTEMS=("linux" "windows")
    for sys in "${SYSTEMS[@]}"; do
        if  [[ "${FILEIN}" = *"${sys}"* ]]; then
            SYSTEM="${sys}"
        fi
    done

    if [ -z "${SYSTEM}" ]; then
        return 1
    else
        echo "${MAIN}/${ARCH}/${SYSTEM}/${BASE}"
    fi
}
setBucket() {
    # Configure the bucket name to use for the upload
    echo ""
    echo "==========================================================="
    echo "Please enter a target bucket name and press [ENTER]:"
    read bucket_name
    # Check if bucket exists, if so create it, if not continue using existing bucket
    if [ "${s3type}" == 'minio' ]; then
        if checkBucket "${AWS_REGION}" "${bucket_name}" >/dev/null; then
            echo "Bucket: ${bucket_name} found!"
            echo "WARNING: Specified bucket is not empty!"
            read -r -p "Are you sure you would like to use this bucket? [y/N] " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                echo "Using specified bucket."
                export S3_BUCKET=${bucket_name}
            else
                setBucket
            fi
        else
            echo "Bucket: ${bucket_name} not found!"
            echo "Creating bucket: ${bucket_name}"
            aws --endpoint-url "${AWS_REGION}" s3api create-bucket --bucket "${bucket_name}"
            export S3_BUCKET=${bucket_name}
        fi
    else
        if aws s3api list-objects --bucket "${bucket_name}" --region "${AWS_REGION}" >/dev/null; then
            echo "Bucket: ${bucket_name} found!"
            echo "WARNING: Specified bucket is not empty!"
            read -r -p "Are you sure you would like to use this bucket? [y/N] " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                echo "Using specified bucket."
                export S3_BUCKET=${bucket_name}
            else
                setBucket
            fi
        else
            echo "Bucket: ${bucket_name} not found!"
            echo "Creating bucket: ${bucket_name}"
            aws s3 mb "s3://${bucket_name}" --region "${AWS_REGION}"
            export S3_BUCKET=${bucket_name}
        fi
    fi
}

checkBucket() {
    region="${1}"
    bucket="${2}"
    aws --endpoint-url "${region}" s3api list-objects --bucket "${bucket}"
}

setRegion() {
    # Sets the region used by the bucket
    if [ "${s3type}" == 'minio' ]; then
        sgroups=("default" "dev" "prod" "acceptance" "live" "blue" "green")
        for i in "${sgroups[@]}"; do
            if curl -s localhost:9631/services/builder-minio/"${i}" > /dev/null; then
                minioIP=$(curl -s localhost:9631/services/builder-minio/"${i}" | jq .sys.ip)
                echo "We've detected your minio instance at: ${minioIP}!"
                read -r -p "Would you like to use this minio instance? [y/N] " response
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                    echo "Setting endpoint to ${minioIP//\"}:9000"
                    if curl -s localhost:9631/services/builder-minio/"${i}" | jq .cfg.use_ssl | grep "true"> /dev/null; then
                        export AWS_REGION="https://${minioIP//\"}:9000"
                    else
                        export AWS_REGION="http://${minioIP//\"}:9000"
                    fi
                    return
                else
                    echo ""
                    echo "==========================================================="
                    echo "Please enter the minio endpoint URI and press [ENTER]:"
                    echo "(http://localhost:9000 || https://10.1.250.4:9000)"
                    echo "==========================================================="
                    read region_name
                    export AWS_REGION=${region_name}
                    return
                fi
            fi
        done
    else
        echo ""
        echo "==========================================================="
        echo "Please enter the region for your bucket and press [ENTER]:"
        echo "(us-west-1 us-east-1 us-west-2 etc )"
        echo "==========================================================="
        read region_name
        export AWS_REGION=${region_name}
    fi
}

putArtifacts() {
    # handles the literal upload of artifacts to the configured s3 bucket
    BODY="${1}"
    BUCKET="${2}"
    REGION="${3}"
    KEY="${4}"

    # upload shellout
    if [  "${s3type}" == 'minio' ]; then
        echo ""
        aws --endpoint-url "${REGION}" s3 cp "${BODY}" s3://"${BUCKET}/${KEY}"
    else
        echo ""
        aws s3api put-object --bucket "${BUCKET}" --key "${KEY}"  --body "${BODY}" --region "${REGION}"
    fi
}

genS3Config() {
    aws configure
}

credSelect() {
    echo ""
    read -r -p "Would you like to use these credentials? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        return
    else
        echo ""
        read -r -p "Would you like to configure with custom credentials now? [y/N]" response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
            genS3Config
        else
            echo "Please reconfigure your AWS credentials and re-run s3migrate."
            exit 1
        fi
    fi
}

credCheck(){
    CREDS=( "${HOME}/.aws/credentials" "${HOME}/.aws/config" "/root/.aws/credentials" "/root/.aws/config")
    for location in "${CREDS[@]}"; do
        if [ -f "${location}" ]; then
            echo ""
            echo "AWS Credentials file located at ${location}"
            cat "${location}"
            credSelect
            credsConfigured=true
            break
        fi

        if [[ ! -z ${AWS_ACCESS_KEY_ID:-} ]]; then
            if [[ ! -z ${AWS_SECRET_ACCESS_KEY:-} ]]; then
                echo ""
                echo "AWS Credentials configured via ENVVAR detected."
                echo ""
                echo "aws_access_key_id=${AWS_ACCESS_KEY_ID:-}"
                echo "aws_secret_access_key=${AWS_SECRET_ACCESS_KEY:-}"
                credSelect
                credsConfigured=true
                break
            else
                echo ""
                echo "WARNING: Incomplete AWS Credentials configured via ENVVAR."
                echo "Make sure to set AWS_ACCESS_KEY_ID && AWS_SECRET_ACCESS_KEY"
                break
            fi
        fi
    done

    if  [ ${credsConfigured} ]; then
        echo ""
        echo "Credentials configured!"
    else
        echo ""
        echo "WARNING: No AWS credentials detected!"
        read -r -p "Would you like to generate them now? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
            genS3Config
        else
            echo "Please configure your AWS credentials and re-run s3migrate."
            echo ""
            exit 1
        fi
    fi
}

welcome() {
    echo "==========================================================="
    echo "###########################################################"
    echo "################ Bldr Artifact S3 Migrate #################"
    echo "###########################################################"
    echo "==========================================================="
    echo "This tool will migrate all of the locally stored packages to s3/minio."
    echo "You must have your AWS/Minio credentials configured on the system."
    credsConfigured=false
    if [ "$s3type" = "minio" ]; then
        echo ""
        echo "It looks like you specified a migration to minio!"
        sgroups=("default" "dev" "prod")
        for i in "${sgroups[@]}"; do
            if curl -s localhost:9631/services/builder-minio/"${i}" | jq .cfg.key_id > /dev/null; then
                access_key_id=$(curl -s localhost:9631/services/builder-minio/default | jq .cfg.key_id)
                secret_access_key=$(curl -s localhost:9631/services/builder-minio/default | jq .cfg.secret_key)
                echo "We were able to detect your minio credentials!"
                echo "(ACCESS_KEY_ID) Username: ${access_key_id}"
                echo "(SECRET ACCESS_KEY) Password: ${secret_access_key}"
                read -r -p "Would you like to use these credentials? [y/N] " response
                    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                        export AWS_ACCESS_KEY_ID=${access_key_id//\"}
                        export AWS_SECRET_ACCESS_KEY=${secret_access_key//\"}
                        return
                    else
                        credCheck
                    fi
            else
                echo "Minio will use whatever credentials you've configured it with."
                echo "If those credentials don't match your aws credentials file, you"
                echo "must specify those custom credentials."
                credCheck
            fi
        done
    else
        credCheck
    fi
}

cleanYoself() {
    echo ""
    echo "==========================================================="
    read -r -p "Would you like to clean all local artifact storage locations? [y/N]" response
        if [[ "${response}" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
            echo "==========================================================="
            echo "###########################################################"
            echo "### CAUTION: This is a destructive operation and cannot ###"
            echo "### be undone or reversed. It is 100% entirely permanent ##"
            echo "###########################################################"
            echo "==========================================================="
            read -r -p "Are you certain you would like to clean local storage? [y/N]" response2
                if [[ "${response2}" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                    echo "Removing all content at /hab/svc/builder-api/data/pkgs/"
                    rm -rf "/hab/svc/builder-api/data/pkgs/"
                    echo "Cleanup complete!"
                else
                    echo "Exiting without removing locally stored artifacts"
                    exit 0
                fi
        else
            echo "Exiting without removing locally stored artifacts"
        fi
}

artifact_dir="/hab/svc/builder-api/data/pkgs"
artifacts=()

if [[ -z ${1:-} ]]; then
    echo "Invalid Argument. Argument must be either 'minio' or 'aws'"
    exit 1
fi

case ${1} in
    'minio')
        echo "Starting migration to minio instance."
        export s3type="minio"
        installDeps
        welcome
        setRegion
        setBucket
        getHarts "${artifact_dir}"
        uploadHarts
    ;;
    'aws')
        echo "Starting migration to AWS S3."
        export s3type="aws"
        installDeps
        welcome
        setRegion
        setBucket
        getHarts "${artifact_dir}"
        uploadHarts
    ;;
    *) echo "Invalid argument. Arg must be 'minio' or 'aws'"
        exit 1
    ;;
esac

cleanYoself
