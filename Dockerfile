FROM mcs07/rdkit:2018.03.1 as rdkit-env

FROM postgres:10 AS rdkit-postgres-build-env

RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    ca-certificates \
    build-essential \
    cmake \
    wget \
    libboost-dev \
    libboost-system-dev \
    libboost-thread-dev \
    libboost-serialization-dev \
    libboost-python-dev \
    libboost-regex-dev \
    libcairo2-dev \
    libeigen3-dev \
    python3-dev \
    python3-numpy \
    patch \
    postgresql-server-dev-10 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy rdkit installation from rdkit-env
COPY --from=rdkit-env /usr/lib/libRDKit* /usr/lib/
COPY --from=rdkit-env /usr/lib/rdkit* /usr/lib/
COPY --from=rdkit-env /usr/share/RDKit /usr/share/RDKit
COPY --from=rdkit-env /usr/include/rdkit /usr/include/rdkit
COPY --from=rdkit-env /usr/lib/python3/dist-packages/rdkit /usr/lib/python3/dist-packages/rdkit

ARG RDKIT_VERSION=Release_2018_03_1
RUN wget --quiet https://github.com/rdkit/rdkit/archive/${RDKIT_VERSION}.tar.gz \
 && tar -xzf ${RDKIT_VERSION}.tar.gz \
 && mv rdkit-${RDKIT_VERSION} rdkit \
 && rm ${RDKIT_VERSION}.tar.gz

WORKDIR /rdkit/Code/PgSQL/rdkit

COPY patches/*.patch /tmp/
RUN patch CMakeLists.txt /tmp/cmakelists.txt.patch \
 && patch adapter.cpp /tmp/adapter.cpp.patch

RUN cmake -Wno-dev \
    -D CMAKE_SYSTEM_PREFIX_PATH=/usr \
    -D CMAKE_INSTALL_PREFIX=/usr \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_MODULE_PATH=/rdkit/Code/cmake/Modules \
    -D RDK_OPTIMIZE_NATIVE=ON \
    -D RDK_BUILD_AVALON_SUPPORT=ON \
    -D RDK_BUILD_INCHI_SUPPORT=ON \
    -D RDKit_DIR=/usr/lib \
    -D PostgreSQL_ROOT=/usr \
    -D PostgreSQL_TYPE_INCLUDE_DIR=/usr/include/postgresql/10/server/ \
    .

RUN make -j $(nproc)

FROM postgres:10 AS rdkit-postgres-env

# Install runtime dependencies
RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    libboost-atomic1.62.0 \
    libboost-chrono1.62.0 \
    libboost-date-time1.62.0 \
    libboost-python1.62.0 \
    libboost-regex1.62.0 \
    libboost-serialization1.62.0 \
    libboost-system1.62.0 \
    libboost-thread1.62.0 \
    libcairo2-dev \
    python3-dev \
    python3-numpy \
    python3-cairo \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy rdkit installation from rdkit-build-env
COPY --from=rdkit-env /usr/lib/libRDKit* /usr/lib/
COPY --from=rdkit-env /usr/lib/rdkit* /usr/lib/
COPY --from=rdkit-env /usr/share/RDKit /usr/share/RDKit
COPY --from=rdkit-env /usr/include/rdkit /usr/include/rdkit
COPY --from=rdkit-env /usr/lib/python3/dist-packages/rdkit /usr/lib/python3/dist-packages/rdkit

# Copy rdkit postgres extension from rdkit-postgres-build-env
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/rdkit--3.5.sql /usr/share/postgresql/10/extension
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/rdkit.control /usr/share/postgresql/10/extension
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/librdkit.so /usr/lib/postgresql/10/lib/rdkit.so
