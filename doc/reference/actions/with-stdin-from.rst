#################
 with-stdin-from
#################

.. highlight:: dune

.. describe:: (with-stdin-from <file> <DSL>)

   Redirect the input from a file.

   Example:

   .. code::

      (with-stdin-from data.txt
       (run ./tests.exe))
