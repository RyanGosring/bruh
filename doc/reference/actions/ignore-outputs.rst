##################
 ignore-<outputs>
##################

.. highlight:: dune

.. describe:: (ignore-<outputs> <DSL>)

   Ignore the output, where ``<outputs>`` is one of: ``stdout``,
   ``stderr``, or ``outputs``.

   Example:

   .. code::

      (ignore-stderr
       (run ./get-conf.exe))
