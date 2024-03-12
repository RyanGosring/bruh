#######
 chdir
#######

.. highlight:: dune

.. describe:: (chdir <dir> <DSL>)

   Run an action in a different directory.

   Example:

   .. code::

      (chdir src
       (run ./build.exe))
