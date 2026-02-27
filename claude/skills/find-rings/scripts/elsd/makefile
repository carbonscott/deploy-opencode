#ELSD - Ellipse and Line Segment Detector
#
#  Copyright (c) 2012 viorica patraucean (vpatrauc@gmail.com)
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program. If not, see <http://www.gnu.org/licenses/>.

SRCS = elsd.c valid_curve.c process_curve.c process_line.c write_svg.c

# SLAC SDF default: versioned .so paths (no -dev symlinks available)
LIBS = /usr/lib64/liblapack.so.3 /usr/lib64/libblas.so.3 -lm

# Standard Linux with dev packages: uncomment below, comment above
# LIBS = -llapack -lblas -lm

elsd: $(SRCS)
	cc -o elsd $(SRCS) $(LIBS)
