########################################
# BEGIN_COPYRIGHT
#
# Copyright (C) 2008-2019 SciDB, Inc.
# All Rights Reserved.
#
# SciDB is free software: you can redistribute it and/or modify
# it under the terms of the AFFERO GNU General Public License as published by
# the Free Software Foundation.
#
# SciDB is distributed "AS-IS" AND WITHOUT ANY WARRANTY OF ANY KIND,
# INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY,
# NON-INFRINGEMENT, OR FITNESS FOR A PARTICULAR PURPOSE. See
# the AFFERO GNU General Public License for the complete license terms.
#
# You should have received a copy of the AFFERO GNU General Public License
# along with SciDB.  If not, see <http://www.gnu.org/licenses/agpl-3.0.html>
#
# END_COPYRIGHT
########################################

if(CPPUNIT_FOUND)
    add_executable(unit_tests unit_tests.cpp
                              ../../src/query/optimizer/OptUnitTests.cpp $<TARGET_OBJECTS:array_lib>)

    target_link_libraries(unit_tests
      PUBLIC ${CPPUNIT_LIBRARIES}
             pqxx
             catalog_lib
             util_lib
             qproc_lib
             util_lib
             system_lib
             Threads::Threads
             ${LIBRT_LIBRARIES}
             ${CMAKE_DL_LIBS}
    )

  install(TARGETS unit_tests
    DESTINATION ${CMAKE_INSTALL_BINDIR}
    COMPONENT scidb-dev-tools
    )

else(CPPUNIT_FOUND)
	message(STATUS "Can not find cppunit library or headers. Unit tests will not build!")
endif(CPPUNIT_FOUND)
