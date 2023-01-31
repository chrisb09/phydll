#!/bin/bash
echo "Remove ./api ./build ..."
export PYTHONPATH=$CWIPI_DIR/lib/python3.9/site-packages:$PYTHONPATH
rm -rf api build
echo -e "Done! \n\n"

echo "sphinx-apidoc ..."
sphinx-apidoc ../src/python/phydll -o ./api --module-first  --no-toc
echo -e "Done! \n\n"

echo "make html ..."
make html
echo -e "Done! \n\n"
