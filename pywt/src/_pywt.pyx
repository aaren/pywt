# Copyright (c) 2006-2012 Filip Wasilewski <http://en.ig.ma/>
# See COPYING for license details.

__doc__ = """Pyrex wrapper for low-level C wavelet transform implementation."""
__all__ = ['MODES', 'Modes', 'Wavelet', 'dwt', 'dwt_coeff_len', 'dwt_max_level',
           'idwt', 'swt', 'swt_max_level', 'upcoef', 'downcoef',
           'wavelist', 'families']

###############################################################################
# imports
import warnings

cimport c_wt
cimport wavelet
cimport common

from libc.math cimport pow, sqrt

ctypedef Py_ssize_t index_t

import numpy as np
cimport numpy as np


ctypedef fused data_t:
    np.float32_t
    np.float64_t


###############################################################################
# Modes
_old_modes = ['zpd',
              'cpd',
              'sym',
              'ppd',
              'sp1',
              'per',
              ]

_attr_deprecation_msg = ('{old} has been renamed to {new} and will '
                         'be unavailable in a future version '
                         'of pywt.')

class _Modes(object):
    """
    Because the most common and practical way of representing digital signals
    in computer science is with finite arrays of values, some extrapolation of
    the input data has to be performed in order to extend the signal before
    computing the :ref:`Discrete Wavelet Transform <ref-dwt>` using the
    cascading filter banks algorithm.

    Depending on the extrapolation method, significant artifacts at the
    signal's borders can be introduced during that process, which in turn may
    lead to inaccurate computations of the :ref:`DWT <ref-dwt>` at the signal's
    ends.

    PyWavelets provides several methods of signal extrapolation that can be
    used to minimize this negative effect:

    zero - zero-padding                   0  0 | x1 x2 ... xn | 0  0
    constant - constant-padding              x1 x1 | x1 x2 ... xn | xn xn
    symmetric - symmetric-padding             x2 x1 | x1 x2 ... xn | xn xn-1
    periodic - periodic-padding            xn-1 xn | x1 x2 ... xn | x1 x2
    smooth - smooth-padding               (1st derivative interpolation)

    DWT performed for these extension modes is slightly redundant, but ensure a
    perfect reconstruction for IDWT. To receive the smallest possible number of
    coefficients, computations can be performed with the periodization mode:

    periodization - like periodic-padding but gives the smallest possible
                    number of decomposition coefficients. IDWT must be
                    performed with the same mode.

    Examples
    --------
    >>> import pywt
    >>> pywt.Modes.modes
        ['zero', 'constant', 'symmetric', 'periodic', 'smooth', 'periodization']
    >>> # The different ways of passing wavelet and mode parameters
    >>> (a, d) = pywt.dwt([1,2,3,4,5,6], 'db2', 'smooth')
    >>> (a, d) = pywt.dwt([1,2,3,4,5,6], pywt.Wavelet('db2'), pywt.Modes.smooth)

    Notes
    -----
    Extending data in context of PyWavelets does not mean reallocation of the
    data in computer's physical memory and copying values, but rather computing
    the extra values only when they are needed.  This feature saves extra
    memory and CPU resources and helps to avoid page swapping when handling
    relatively big data arrays on computers with low physical memory.

    """
    zero = common.MODE_ZEROPAD
    constant = common.MODE_CONSTANT_EDGE
    symmetric = common.MODE_SYMMETRIC
    periodic = common.MODE_PERIODIC
    smooth = common.MODE_SMOOTH
    periodization = common.MODE_PERIODIZATION

    modes = ["zero", "constant", "symmetric", "periodic", "smooth",
             "periodization"]

    def from_object(self, mode):
        if isinstance(mode, int):
            if mode <= common.MODE_INVALID or mode >= common.MODE_MAX:
                raise ValueError("Invalid mode.")
            m = mode
        else:
            try:
                m = getattr(Modes, mode)
            except AttributeError:
                raise ValueError("Unknown mode name '%s'." % mode)

        return m

    def __getattr__(self, mode):
        # catch deprecated mode names
        if mode in _old_modes:
            new_mode = Modes.modes[_old_modes.index(mode)]
            warnings.warn(_attr_deprecation_msg.format(old=mode, new=new_mode),
                          DeprecationWarning)
            mode = new_mode
        return Modes.__getattribute__(mode)


Modes = _Modes()


class _DeprecatedMODES(_Modes):
    msg = ("MODES has been renamed to Modes and will be "
           "removed in a future version of pywt.")

    def __getattribute__(self, attr):
        """Override so that deprecation warning is shown
        every time MODES is used.

        N.B. have to use __getattribute__ as well as __getattr__
        to ensure warning on e.g. `MODES.symmetric`.
        """
        if not attr.startswith('_'):
            warnings.warn(_DeprecatedMODES.msg, DeprecationWarning)
        return _Modes.__getattribute__(self, attr)

    def __getattr__(self, attr):
        """Override so that deprecation warning is shown
        every time MODES is used.
        """
        warnings.warn(_DeprecatedMODES.msg, DeprecationWarning)
        return _Modes.__getattr__(self, attr)


MODES = _DeprecatedMODES()

###############################################################################
# Wavelet

include "wavelets_list.pxi"  # __wname_to_code

cdef object wname_to_code(name):
    cdef object code_number
    try:
        code_number = __wname_to_code[name]
        assert len(code_number) == 2
        assert isinstance(code_number[0], int)
        assert isinstance(code_number[1], int)
        return code_number
    except KeyError:
        raise ValueError("Unknown wavelet name '%s', check wavelist() for the "
                         "list of available builtin wavelets." % name)


def wavelist(family=None):
    """
    wavelist(family=None)

    Returns list of available wavelet names for the given family name.

    Parameters
    ----------
    family : {'haar', 'db', 'sym', 'coif', 'bior', 'rbio', 'dmey'}
        Short family name.  If the family name is None (default) then names
        of all the built-in wavelets are returned. Otherwise the function
        returns names of wavelets that belong to the given family.

    Returns
    -------
    wavelist : list
        List of available wavelet names

    Examples
    --------
    >>> import pywt
    >>> pywt.wavelist('coif')
    ['coif1', 'coif2', 'coif3', 'coif4', 'coif5']

    """
    cdef object wavelets, sorting_list
    sorting_list = []  # for natural sorting order
    wavelets = []
    cdef object name
    if family is None:
        for name in __wname_to_code:
            sorting_list.append((name[:2], len(name), name))
    elif family in __wfamily_list_short:
        for name in __wname_to_code:
            if name.startswith(family):
                sorting_list.append((name[:2], len(name), name))
    else:
        raise ValueError("Invalid short family name '%s'." % family)

    sorting_list.sort()
    for x, x, name in sorting_list:
        wavelets.append(name)
    return wavelets


def families(int short=True):
    """
    families(short=True)

    Returns a list of available built-in wavelet families.

    Currently the built-in families are:

    * Haar (``haar``)
    * Daubechies (``db``)
    * Symlets (``sym``)
    * Coiflets (``coif``)
    * Biorthogonal (``bior``)
    * Reverse biorthogonal (``rbio``)
    * `"Discrete"` FIR approximation of Meyer wavelet (``dmey``)

    Parameters
    ----------
    short : bool, optional
        Use short names (default: True).

    Returns
    -------
    families : list
        List of available wavelet families.

    Examples
    --------
    >>> import pywt
    >>> pywt.families()
    ['haar', 'db', 'sym', 'coif', 'bior', 'rbio', 'dmey']
    >>> pywt.families(short=False)
    ['Haar', 'Daubechies', 'Symlets', 'Coiflets', 'Biorthogonal',
     'Reverse biorthogonal', 'Discrete Meyer (FIR Approximation)']

    """
    if short:
        return __wfamily_list_short[:]
    return __wfamily_list_long[:]


cdef public class Wavelet [type WaveletType, object WaveletObject]:
    """
    Wavelet(name, filter_bank=None) object describe properties of
    a wavelet identified by name.

    In order to use a built-in wavelet the parameter name must be
    a valid name from the wavelist() list.
    To create a custom wavelet object, filter_bank parameter must
    be specified. It can be either a list of four filters or an object
    that a `filter_bank` attribute which returns a list of four
    filters - just like the Wavelet instance itself.

    """
    cdef wavelet.Wavelet* w

    cdef readonly name
    cdef readonly number

    #cdef readonly properties
    def __cinit__(self, name=u"", object filter_bank=None):
        cdef object family_code, family_number
        cdef object filters
        cdef index_t filter_length
        cdef object dec_lo, dec_hi, rec_lo, rec_hi

        if not name and filter_bank is None:
            raise TypeError("Wavelet name or filter bank must be specified.")

        if filter_bank is None:
            # builtin wavelet
            self.name = name.lower()
            family_code, family_number = wname_to_code(self.name)
            self.w = <wavelet.Wavelet*> wavelet.wavelet(family_code, family_number)

            if self.w is NULL:
                raise ValueError("Invalid wavelet name.")
            self.number = family_number
        else:
            if hasattr(filter_bank, "filter_bank"):
                filters = filter_bank.filter_bank
                if len(filters) != 4:
                    raise ValueError("Expected filter bank with 4 filters, "
                    "got filter bank with %d filters." % len(filters))
            elif hasattr(filter_bank, "get_filters_coeffs"):
                msg = ("Creating custom Wavelets using objects that define "
                       "`get_filters_coeffs` method is deprecated. "
                       "The `filter_bank` parameter should define a "
                       "`filter_bank` attribute instead of "
                       "`get_filters_coeffs` method.")
                warnings.warn(msg, DeprecationWarning)
                filters = filter_bank.get_filters_coeffs()
                if len(filters) != 4:
                    msg = ("Expected filter bank with 4 filters, got filter "
                           "bank with %d filters." % len(filters))
                    raise ValueError(msg)
            else:
                filters = filter_bank
                if len(filters) != 4:
                    msg = ("Expected list of 4 filters coefficients, "
                           "got %d filters." % len(filters))
                    raise ValueError(msg)
            try:
                dec_lo = np.asarray(filters[0], dtype=np.float64)
                dec_hi = np.asarray(filters[1], dtype=np.float64)
                rec_lo = np.asarray(filters[2], dtype=np.float64)
                rec_hi = np.asarray(filters[3], dtype=np.float64)
            except TypeError:
                raise ValueError("Filter bank with numeric values required.")

            if not (1 == dec_lo.ndim == dec_hi.ndim ==
                         rec_lo.ndim == rec_hi.ndim):
                raise ValueError("All filters in filter bank must be 1D.")

            filter_length = len(dec_lo)
            if not (0 < filter_length == len(dec_hi) == len(rec_lo) ==
                                         len(rec_hi)) > 0:
                raise ValueError("All filters in filter bank must have "
                                 "length greater than 0.")

            self.w = <wavelet.Wavelet*> wavelet.blank_wavelet(filter_length)
            if self.w is NULL:
                raise MemoryError("Could not allocate memory for given "
                                  "filter bank.")

            # copy values to struct
            copy_object_to_float32_array(dec_lo, self.w.dec_lo_float)
            copy_object_to_float32_array(dec_hi, self.w.dec_hi_float)
            copy_object_to_float32_array(rec_lo, self.w.rec_lo_float)
            copy_object_to_float32_array(rec_hi, self.w.rec_hi_float)

            copy_object_to_float64_array(dec_lo, self.w.dec_lo_double)
            copy_object_to_float64_array(dec_hi, self.w.dec_hi_double)
            copy_object_to_float64_array(rec_lo, self.w.rec_lo_double)
            copy_object_to_float64_array(rec_hi, self.w.rec_hi_double)

            self.name = name

    def __dealloc__(self):
        if self.w is not NULL:
            # if w._builtin is 0 then it frees the memory for the filter arrays
            wavelet.free_wavelet(self.w)
            self.w = NULL

    def __len__(self):
        return self.w.dec_len

    property dec_lo:
        "Lowpass decomposition filter"
        def __get__(self):
            return float64_array_to_list(self.w.dec_lo_double, self.w.dec_len)

    property dec_hi:
        "Highpass decomposition filter"
        def __get__(self):
            return float64_array_to_list(self.w.dec_hi_double, self.w.dec_len)

    property rec_lo:
        "Lowpass reconstruction filter"
        def __get__(self):
            return float64_array_to_list(self.w.rec_lo_double, self.w.rec_len)

    property rec_hi:
        "Highpass reconstruction filter"
        def __get__(self):
            return float64_array_to_list(self.w.rec_hi_double, self.w.rec_len)

    property rec_len:
        "Reconstruction filters length"
        def __get__(self):
            return self.w.rec_len

    property dec_len:
        "Decomposition filters length"
        def __get__(self):
            return self.w.dec_len

    property family_name:
        "Wavelet family name"
        def __get__(self):
            return self.w.family_name.decode('latin-1')

    property short_family_name:
        "Short wavelet family name"
        def __get__(self):
            return self.w.short_name.decode('latin-1')

    property orthogonal:
        "Is orthogonal"
        def __get__(self):
            return bool(self.w.orthogonal)
        def __set__(self, int value):
            self.w.orthogonal = (value != 0)

    property biorthogonal:
        "Is biorthogonal"
        def __get__(self):
            return bool(self.w.biorthogonal)
        def __set__(self, int value):
            self.w.biorthogonal = (value != 0)

    property symmetry:
        "Wavelet symmetry"
        def __get__(self):
            if self.w.symmetry == wavelet.ASYMMETRIC:
                return "asymmetric"
            elif self.w.symmetry == wavelet.NEAR_SYMMETRIC:
                return "near symmetric"
            elif self.w.symmetry == wavelet.SYMMETRIC:
                return "symmetric"
            else:
                return "unknown"

    property vanishing_moments_psi:
        "Number of vanishing moments for wavelet function"
        def __get__(self):
            if self.w.vanishing_moments_psi >= 0:
                return self.w.vanishing_moments_psi

    property vanishing_moments_phi:
        "Number of vanishing moments for scaling function"
        def __get__(self):
            if self.w.vanishing_moments_phi >= 0:
                return self.w.vanishing_moments_phi

    property _builtin:
        """Returns True if the wavelet is built-in one (not created with
        custom filter bank).
        """
        def __get__(self):
            return bool(self.w._builtin)

    property filter_bank:
        """Returns tuple of wavelet filters coefficients
        (dec_lo, dec_hi, rec_lo, rec_hi)
        """
        def __get__(self):
            return (self.dec_lo, self.dec_hi, self.rec_lo, self.rec_hi)

    def get_filters_coeffs(self):
        warnings.warn("The `get_filters_coeffs` method is deprecated. "
                      "Use `filter_bank` attribute instead.", DeprecationWarning)
        return self.filter_bank

    property inverse_filter_bank:
        """Tuple of inverse wavelet filters coefficients
        (rec_lo[::-1], rec_hi[::-1], dec_lo[::-1], dec_hi[::-1])
        """
        def __get__(self):
            return (self.rec_lo[::-1], self.rec_hi[::-1], self.dec_lo[::-1],
                    self.dec_hi[::-1])

    def get_reverse_filters_coeffs(self):
        warnings.warn("The `get_reverse_filters_coeffs` method is deprecated. "
                      "Use `inverse_filter_bank` attribute instead.",
                      DeprecationWarning)
        return self.inverse_filter_bank

    def wavefun(self, int level=8):
        """
        wavefun(self, level=8)

        Calculates approximations of scaling function (`phi`) and wavelet
        function (`psi`) on xgrid (`x`) at a given level of refinement.

        Parameters
        ----------
        level : int, optional
            Level of refinement (default: 8).

        Returns
        -------
        [phi, psi, x] : array_like
            For orthogonal wavelets returns scaling function, wavelet function
            and xgrid - [phi, psi, x].

        [phi_d, psi_d, phi_r, psi_r, x] : array_like
            For biorthogonal wavelets returns scaling and wavelet function both
            for decomposition and reconstruction and xgrid

        Examples
        --------
        >>> import pywt
        >>> # Orthogonal
        >>> wavelet = pywt.Wavelet('db2')
        >>> phi, psi, x = wavelet.wavefun(level=5)
        >>> # Biorthogonal
        >>> wavelet = pywt.Wavelet('bior3.5')
        >>> phi_d, psi_d, phi_r, psi_r, x = wavelet.wavefun(level=5)

        """
        cdef index_t filter_length "filter_length"
        cdef index_t right_extent_length "right_extent_length"
        cdef index_t output_length "output_length"
        cdef index_t keep_length "keep_length"
        cdef double n "n"
        cdef double p "p"
        cdef double mul "mul"
        cdef Wavelet other "other"
        cdef phi_d, psi_d, phi_r, psi_r

        n = pow(sqrt(2.), <double>level)
        p = (pow(2., <double>level))

        if self.w.orthogonal:
            filter_length = self.w.dec_len
            output_length = <index_t> ((filter_length-1) * p + 1)
            keep_length = get_keep_length(output_length, level, filter_length)
            output_length = fix_output_length(output_length, keep_length)

            right_extent_length = get_right_extent_length(output_length,
                                                          keep_length)

            # phi, psi, x
            return [np.concatenate(([0.], keep(upcoef('a', [n], self, level),
                                    keep_length), np.zeros(right_extent_length))),
                    np.concatenate(([0.], keep(upcoef('d', [n], self, level),
                                    keep_length), np.zeros(right_extent_length))),
                    np.linspace(0.0, (output_length-1)/p, output_length)]
        else:
            mul = 1
            if self.w.biorthogonal:
                if (self.w.vanishing_moments_psi % 4) != 1:
                    mul = -1

            other = Wavelet(filter_bank=self.inverse_filter_bank)

            filter_length  = other.w.dec_len
            output_length = <index_t> ((filter_length-1) * p)
            keep_length = get_keep_length(output_length, level, filter_length)
            output_length = fix_output_length(output_length, keep_length)
            right_extent_length = get_right_extent_length(output_length, keep_length)

            phi_d  = np.concatenate(([0.], keep(upcoef('a', [n], other, level),
                                     keep_length), np.zeros(right_extent_length)))
            psi_d  = np.concatenate(([0.], keep(upcoef('d', [mul*n], other,
                                                       level), keep_length),
                                     np.zeros(right_extent_length)))

            filter_length = self.w.dec_len
            output_length = <index_t> ((filter_length-1) * p)
            keep_length = get_keep_length(output_length, level, filter_length)
            output_length = fix_output_length(output_length, keep_length)
            right_extent_length = get_right_extent_length(output_length, keep_length)

            phi_r  = np.concatenate(([0.], keep(upcoef('a', [n], self, level),
                                     keep_length), np.zeros(right_extent_length)))
            psi_r  = np.concatenate(([0.], keep(upcoef('d', [mul*n], self,
                                                       level), keep_length),
                                     np.zeros(right_extent_length)))

            return [phi_d, psi_d, phi_r, psi_r,
                    np.linspace(0.0, (output_length - 1) / p, output_length)]

    def __str__(self):
        s = []
        for x in [
            u"Wavelet %s" % self.name,
            u"  Family name:    %s" % self.family_name,
            u"  Short name:     %s" % self.short_family_name,
            u"  Filters length: %d" % self.dec_len,
            u"  Orthogonal:     %s" % self.orthogonal,
            u"  Biorthogonal:   %s" % self.biorthogonal,
            u"  Symmetry:       %s" % self.symmetry
            ]:
            s.append(x.rstrip())
        return u'\n'.join(s)

    def __repr__(self):
        repr = "{module}.{classname}(name='{name}', filter_bank={filter_bank})"
        return repr.format(module=type(self).__module__,
                           classname=type(self).__name__,
                           name=self.name,
                           filter_bank=self.filter_bank)


cdef index_t get_keep_length(index_t output_length,
                             int level, index_t filter_length):
    cdef index_t lplus "lplus"
    cdef index_t keep_length "keep_length"
    cdef int i "i"
    lplus = filter_length - 2
    keep_length = 1
    for i in range(level):
        keep_length = 2*keep_length+lplus
    return keep_length

cdef index_t fix_output_length(index_t output_length, index_t keep_length):
    if output_length-keep_length-2 < 0:
        output_length = keep_length+2
    return output_length

cdef index_t get_right_extent_length(index_t output_length, index_t keep_length):
    return output_length - keep_length - 1


def wavelet_from_object(wavelet):
    return c_wavelet_from_object(wavelet)


cdef c_wavelet_from_object(wavelet):
    if isinstance(wavelet, Wavelet):
        return wavelet
    else:
        return Wavelet(wavelet)


###############################################################################
# DWT

def dwt_max_level(data_len, filter_len):
    """
    dwt_max_level(data_len, filter_len)

    Compute the maximum useful level of decomposition.

    Parameters
    ----------
    data_len : int
        Input data length.
    filter_len : int
        Wavelet filter length.

    Returns
    -------
    max_level : int
        Maximum level.

    Examples
    --------
    >>> import pywt
    >>> w = pywt.Wavelet('sym5')
    >>> pywt.dwt_max_level(data_len=1000, filter_len=w.dec_len)
    6
    >>> pywt.dwt_max_level(1000, w)
    6
    """
    if isinstance(filter_len, Wavelet):
        return common.dwt_max_level(data_len, filter_len.dec_len)
    else:
        return common.dwt_max_level(data_len, filter_len)


def dwt(object data, object wavelet, object mode='symmetric'):
    """
    (cA, cD) = dwt(data, wavelet, mode='symmetric')

    Single level Discrete Wavelet Transform.

    Parameters
    ----------
    data : array_like
        Input signal
    wavelet : Wavelet object or name
        Wavelet to use
    mode : str, optional (default: 'symmetric')
        Signal extension mode, see Modes

    Returns
    -------
    (cA, cD) : tuple
        Approximation and detail coefficients.

    Notes
    -----
    Length of coefficients arrays depends on the selected mode:
    for all modes except periodization:
        len(cA) == len(cD) == floor((len(data) + wavelet.dec_len - 1) / 2)
    for periodization mode ("per"):
        len(cA) == len(cD) == ceil(len(data) / 2)

    Examples
    --------
    >>> import pywt
    >>> (cA, cD) = pywt.dwt([1, 2, 3, 4, 5, 6], 'db1')
    >>> cA
    [ 2.12132034  4.94974747  7.77817459]
    >>> cD
    [-0.70710678 -0.70710678 -0.70710678]

    """
    if np.iscomplexobj(data):
        data = np.asarray(data)
        cA_r, cD_r = dwt(data.real, wavelet, mode)
        cA_i, cD_i = dwt(data.imag, wavelet, mode)
        return  (cA_r + 1j*cA_i, cD_r + 1j*cD_i)

    # accept array_like input; make a copy to ensure a contiguous array
    dt = _check_dtype(data)
    data = np.array(data, dtype=dt)
    if data.ndim != 1:
        raise ValueError("dwt requires a 1D data array.")
    return _dwt(data, wavelet, mode)


def _dwt(np.ndarray[data_t, ndim=1] data, object wavelet, object mode='symmetric'):
    """See `dwt` docstring for details."""
    cdef np.ndarray[data_t, ndim=1, mode="c"] cA, cD
    cdef Wavelet w
    cdef common.MODE mode_

    w = c_wavelet_from_object(wavelet)
    mode_ = _try_mode(mode)

    data = np.array(data)
    output_len = common.dwt_buffer_length(data.size, w.dec_len, mode_)
    if output_len < 1:
        raise RuntimeError("Invalid output length.")

    cA = np.zeros(output_len, data.dtype)
    cD = np.zeros(output_len, data.dtype)

    if data_t == np.float64_t:
        if (c_wt.double_dec_a(&data[0], data.size, w.w,
                              &cA[0], cA.size, mode_) < 0
            or
            c_wt.double_dec_d(&data[0], data.size, w.w,
                              &cD[0], cD.size, mode_) < 0):
            raise RuntimeError("C dwt failed.")
    elif data_t == np.float32_t:
        if (c_wt.float_dec_a(&data[0], data.size, w.w,
                             &cA[0], cA.size, mode_) < 0
            or
            c_wt.float_dec_d(&data[0], data.size, w.w,
                             &cD[0], cD.size, mode_) < 0):
            raise RuntimeError("C dwt failed.")
    else:
        raise RuntimeError("Invalid data type.")

    return (cA, cD)


cpdef dwt_axis(np.ndarray data, object wavelet, object mode='symmetric', unsigned int axis=0):
    cdef Wavelet w = c_wavelet_from_object(wavelet)
    cdef common.MODE _mode = _try_mode(mode)
    cdef common.ArrayInfo data_info, output_info
    cdef np.ndarray cD, cA
    cdef size_t[::1] output_shape

    data = data.astype(_check_dtype(data), copy=False)

    output_shape = (<size_t [:data.ndim]> <size_t *> data.shape).copy()
    output_shape[axis] = common.dwt_buffer_length(data.shape[axis], w.dec_len, _mode)

    cA = np.empty(output_shape, data.dtype)
    cD = np.empty(output_shape, data.dtype)

    data_info.ndim = data.ndim
    data_info.strides = <index_t *> data.strides
    data_info.shape = <size_t *> data.shape

    output_info.ndim = cA.ndim
    output_info.strides = <index_t *> cA.strides
    output_info.shape = <size_t *> cA.shape

    if data.dtype == np.float64:
        if c_wt.double_downcoef_axis(<double *> data.data, data_info,
                                     <double *> cA.data, output_info,
                                     w.w, axis, common.COEF_APPROX, _mode):
            raise RuntimeError("C wavelet transform failed")
        if c_wt.double_downcoef_axis(<double *> data.data, data_info,
                                     <double *> cD.data, output_info,
                                     w.w, axis, common.COEF_DETAIL, _mode):
            raise RuntimeError("C wavelet transform failed")
    elif data.dtype == np.float32:
        if c_wt.float_downcoef_axis(<float *> data.data, data_info,
                                    <float *> cA.data, output_info,
                                    w.w, axis, common.COEF_APPROX, _mode):
            raise RuntimeError("C wavelet transform failed")
        if c_wt.float_downcoef_axis(<float *> data.data, data_info,
                                    <float *> cD.data, output_info,
                                    w.w, axis, common.COEF_DETAIL, _mode):
            raise RuntimeError("C wavelet transform failed")
    else:
        raise TypeError("Array must be floating point, not {}"
                        .format(data.dtype))
    return (cA, cD)


cpdef idwt_axis(np.ndarray coefs_a, np.ndarray coefs_d, object wavelet,
                object mode='symmetric', unsigned int axis=0):
    cdef Wavelet w = c_wavelet_from_object(wavelet)
    cdef common.ArrayInfo a_info, d_info, output_info
    cdef np.ndarray output
    cdef np.dtype output_dtype
    cdef size_t[::1] output_shape
    cdef common.MODE _mode = _try_mode(mode)

    if coefs_a is not None:
        if coefs_d is not None and coefs_d.dtype.itemsize > coefs_a.dtype.itemsize:
            coefs_a = coefs_a.astype(_check_dtype(coefs_d), copy=False)
        else:
            coefs_a = coefs_a.astype(_check_dtype(coefs_a), copy=False)
        a_info.ndim = coefs_a.ndim
        a_info.strides = <index_t *> coefs_a.strides
        a_info.shape = <size_t *> coefs_a.shape
    if coefs_d is not None:
        if coefs_a is not None and coefs_a.dtype.itemsize > coefs_d.dtype.itemsize:
            coefs_d = coefs_d.astype(_check_dtype(coefs_a), copy=False)
        else:
            coefs_d = coefs_d.astype(_check_dtype(coefs_d), copy=False)
        d_info.ndim = coefs_d.ndim
        d_info.strides = <index_t *> coefs_d.strides
        d_info.shape = <size_t *> coefs_d.shape

    if coefs_a is not None:
        output_shape = (<size_t [:coefs_a.ndim]> <size_t *> coefs_a.shape).copy()
        output_shape[axis] = common.idwt_buffer_length(coefs_a.shape[axis],
                                                       w.rec_len, _mode)
        output_dtype = coefs_a.dtype
    elif coefs_d is not None:
        output_shape = (<size_t [:coefs_d.ndim]> <size_t *> coefs_d.shape).copy()
        output_shape[axis] = common.idwt_buffer_length(coefs_d.shape[axis],
                                                       w.rec_len, _mode)
        output_dtype = coefs_d.dtype
    else:
        return None;

    output = np.empty(output_shape, output_dtype)

    output_info.ndim = output.ndim
    output_info.strides = <index_t *> output.strides
    output_info.shape = <size_t *> output.shape

    if output.dtype == np.float64:
        if c_wt.double_idwt_axis(<double *> coefs_a.data if coefs_a is not None else NULL,
                                 &a_info if coefs_a is not None else NULL,
                                 <double *> coefs_d.data if coefs_d is not None else NULL,
                                 &d_info if coefs_d is not None else NULL,
                                 <double *> output.data, output_info,
                                 w.w, axis, _mode):
            raise RuntimeError("C inverse wavelet transform failed")
    if output.dtype == np.float32:
        if c_wt.float_idwt_axis(<float *> coefs_a.data if coefs_a is not None else NULL,
                                &a_info if coefs_a is not None else NULL,
                                <float *> coefs_d.data if coefs_d is not None else NULL,
                                &d_info if coefs_d is not None else NULL,
                                <float *> output.data, output_info,
                                w.w, axis, _mode):
            raise RuntimeError("C inverse wavelet transform failed")

    return output


def dwt_coeff_len(data_len, filter_len, mode='symmetric'):
    """
    dwt_coeff_len(data_len, filter_len, mode='symmetric')

    Returns length of dwt output for given data length, filter length and mode

    Parameters
    ----------
    data_len : int
        Data length.
    filter_len : int
        Filter length.
    mode : str, optional (default: 'symmetric')
        Signal extension mode, see Modes

    Returns
    -------
    len : int
        Length of dwt output.

    Notes
    -----
    For all modes except periodization::

        len(cA) == len(cD) == floor((len(data) + wavelet.dec_len - 1) / 2)

    for periodization mode ("per")::

        len(cA) == len(cD) == ceil(len(data) / 2)

    """
    cdef index_t filter_len_

    if isinstance(filter_len, Wavelet):
        filter_len_ = filter_len.dec_len
    else:
        filter_len_ = filter_len

    if data_len < 1:
        raise ValueError("Value of data_len value must be greater than zero.")
    if filter_len_ < 1:
        raise ValueError("Value of filter_len must be greater than zero.")

    return common.dwt_buffer_length(data_len, filter_len_, _try_mode(mode))


###############################################################################
# idwt

def _try_mode(mode):
    try:
        return Modes.from_object(mode)
    except ValueError as e:
        if "Unknown mode name" in str(e):
            raise
        raise TypeError("Invalid mode: {0}".format(str(mode)))


cdef np.dtype _check_dtype(data):
    """Check for cA/cD input what (if any) the dtype is."""
    cdef np.dtype dt
    try:
        dt = data.dtype
        if dt not in (np.float64, np.float32):
            # integer input was always accepted; convert to float64
            dt = np.dtype('float64')
    except AttributeError:
        dt = np.dtype('float64')
    return dt


def idwt(cA, cD, object wavelet, object mode='symmetric'):
    """
    idwt(cA, cD, wavelet, mode='symmetric')

    Single level Inverse Discrete Wavelet Transform

    Parameters
    ----------
    cA : array_like or None
        Approximation coefficients.  If None, will be set to array of zeros
        with same shape as `cD`.
    cD : array_like or None
        Detail coefficients.  If None, will be set to array of zeros
        with same shape as `cA`.
    wavelet : Wavelet object or name
        Wavelet to use
    mode : str, optional (default: 'symmetric')
        Signal extension mode, see Modes

    Returns
    -------
    rec: array_like
        Single level reconstruction of signal from given coefficients.

    """
    # accept array_like input; make a copy to ensure a contiguous array

    if cA is None and cD is None:
        raise ValueError("At least one coefficient parameter must be "
                         "specified.")

    # for complex inputs: compute real and imaginary separately then combine
    if ((cA is not None) and np.iscomplexobj(cA)) or ((cD is not None) and
            np.iscomplexobj(cD)):
        if cA is None:
            cD = np.asarray(cD)
            cA = np.zeros_like(cD)
        elif cD is None:
            cA = np.asarray(cA)
            cD = np.zeros_like(cA)
        return (idwt(cA.real, cD.real, wavelet, mode) +
                1j*idwt(cA.imag, cD.imag, wavelet, mode))

    if cA is not None:
        dt = _check_dtype(cA)
        cA = np.array(cA, dtype=dt)
        if cA.ndim != 1:
            raise ValueError("idwt requires 1D coefficient arrays.")
    if cD is not None:
        dt = _check_dtype(cD)
        cD = np.array(cD, dtype=dt)
        if cD.ndim != 1:
            raise ValueError("idwt requires 1D coefficient arrays.")

    if cA is not None and cD is not None:
        if cA.dtype != cD.dtype:
            # need to upcast to common type
            cA = cA.astype(np.float64)
            cD = cD.astype(np.float64)
    elif cA is None:
        cA = np.zeros_like(cD)
    elif cD is None:
        cD = np.zeros_like(cA)

    return _idwt(cA, cD, wavelet, mode)


def _idwt(np.ndarray[data_t, ndim=1, mode="c"] cA,
          np.ndarray[data_t, ndim=1, mode="c"] cD,
          object wavelet, object mode='symmetric'):
    """See `idwt` for details"""

    cdef index_t input_len

    cdef Wavelet w
    cdef common.MODE mode_

    w = c_wavelet_from_object(wavelet)
    mode_ = _try_mode(mode)

    cdef np.ndarray[data_t, ndim=1, mode="c"] rec
    cdef index_t rec_len

    # check for size difference between arrays
    if cA.size != cD.size:
        raise ValueError("Coefficients arrays must have the same size.")
    else:
        input_len = cA.size

    # find reconstruction buffer length
    rec_len = common.idwt_buffer_length(input_len, w.rec_len, mode_)
    if rec_len < 1:
        msg = ("Invalid coefficient arrays length for specified wavelet. "
               "Wavelet and mode must be the same as used for decomposition.")
        raise ValueError(msg)

    # allocate buffer
    if cA is not None:
        rec = np.zeros(rec_len, dtype=cA.dtype)
    else:
        rec = np.zeros(rec_len, dtype=cD.dtype)

    # call idwt func.  one of cA/cD can be None, then only
    # reconstruction of non-null part will be performed
    if data_t is np.float64_t:
        if c_wt.double_idwt(&cA[0], cA.size,
                            &cD[0], cD.size,
                            &rec[0], rec.size,
                            w.w, mode_) < 0:
            raise RuntimeError("C idwt failed.")
    elif data_t == np.float32_t:
        if c_wt.float_idwt(&cA[0], cA.size,
                           &cD[0], cD.size,
                           &rec[0], rec.size,
                           w.w, mode_) < 0:
            raise RuntimeError("C idwt failed.")
    else:
        raise RuntimeError("Invalid data type.")

    return rec


###############################################################################
# upcoef & downcoef

def upcoef(part, coeffs, wavelet, level=1, take=0):
    """
    upcoef(part, coeffs, wavelet, level=1, take=0)

    Direct reconstruction from coefficients.

    Parameters
    ----------
    part : str
        Coefficients type:
        * 'a' - approximations reconstruction is performed
        * 'd' - details reconstruction is performed
    coeffs : array_like
        Coefficients array to recontruct
    wavelet : Wavelet object or name
        Wavelet to use
    level : int, optional
        Multilevel reconstruction level.  Default is 1.
    take : int, optional
        Take central part of length equal to 'take' from the result.
        Default is 0.

    Returns
    -------
    rec : ndarray
        1-D array with reconstructed data from coefficients.

    See Also
    --------
    downcoef

    Examples
    --------
    >>> import pywt
    >>> data = [1,2,3,4,5,6]
    >>> (cA, cD) = pywt.dwt(data, 'db2', 'smooth')
    >>> pywt.upcoef('a', cA, 'db2') + pywt.upcoef('d', cD, 'db2')
    [-0.25       -0.4330127   1.          2.          3.          4.          5.
      6.          1.78589838 -1.03108891]
    >>> n = len(data)
    >>> pywt.upcoef('a', cA, 'db2', take=n) + pywt.upcoef('d', cD, 'db2', take=n)
    [ 1.  2.  3.  4.  5.  6.]

    """
    if np.iscomplexobj(coeffs):
        return (upcoef(part, coeffs.real, wavelet, level, take) +
                1j*upcoef(part, coeffs.imag, wavelet, level, take))
    # accept array_like input; make a copy to ensure a contiguous array
    dt = _check_dtype(coeffs)
    coeffs = np.array(coeffs, dtype=dt)
    return _upcoef(part, coeffs, wavelet, level, take)


def _upcoef(part, np.ndarray[data_t, ndim=1, mode="c"] coeffs, wavelet,
            int level=1, int take=0):
    cdef Wavelet w
    cdef np.ndarray[data_t, ndim=1, mode="c"] rec
    cdef int i, do_rec_a
    cdef index_t rec_len, left_bound, right_bound

    rec_len = 0

    if part not in ('a', 'd'):
        raise ValueError("Argument 1 must be 'a' or 'd', not '%s'." % part)
    do_rec_a = (part == 'a')

    w = c_wavelet_from_object(wavelet)

    if level < 1:
        raise ValueError("Value of level must be greater than 0.")

    for i in range(level):
        # output len
        rec_len = common.reconstruction_buffer_length(coeffs.size, w.dec_len)
        if rec_len < 1:
            raise RuntimeError("Invalid output length.")

        # reconstruct
        rec = np.zeros(rec_len, dtype=coeffs.dtype)

        # To mirror multi-level wavelet reconstruction behaviour, when detail
        # reconstruction is requested, the dec_d variant is only called at the
        # first level to generate the approximation coefficients at the second
        # level.  Subsequent levels apply the reconstruction filter.
        if do_rec_a:
            if data_t is np.float64_t:
                if c_wt.double_rec_a(&coeffs[0], coeffs.size, w.w,
                                     &rec[0], rec.size) < 0:
                    raise RuntimeError("C rec_a failed.")
            elif data_t is np.float32_t:
                if c_wt.float_rec_a(&coeffs[0], coeffs.size, w.w,
                                    &rec[0], rec.size) < 0:
                    raise RuntimeError("C rec_a failed.")
            else:
                raise RuntimeError("Invalid data type.")
        else:
            if data_t is np.float64_t:
                if c_wt.double_rec_d(&coeffs[0], coeffs.size, w.w,
                                     &rec[0], rec.size) < 0:
                    raise RuntimeError("C rec_d failed.")
            elif data_t is np.float32_t:
                if c_wt.float_rec_d(&coeffs[0], coeffs.size, w.w,
                                    &rec[0], rec.size) < 0:
                    raise RuntimeError("C rec_d failed.")
            else:
                raise RuntimeError("Invalid data type.")
            # switch to approximation filter for subsequent levels
            do_rec_a = 1

        # TODO: this algorithm needs some explaining
        coeffs = rec

    if take > 0 and take < rec_len:
        left_bound = right_bound = (rec_len-take) // 2
        if (rec_len-take) % 2:
            # right_bound must never be zero for indexing to work
            right_bound = right_bound + 1

        return rec[left_bound:-right_bound]

    return rec


def downcoef(part, data, wavelet, mode='symmetric', level=1):
    """
    downcoef(part, data, wavelet, mode='symmetric', level=1)

    Partial Discrete Wavelet Transform data decomposition.

    Similar to `pywt.dwt`, but computes only one set of coefficients.
    Useful when you need only approximation or only details at the given level.

    Parameters
    ----------
    part : str
        Coefficients type:

        * 'a' - approximations reconstruction is performed
        * 'd' - details reconstruction is performed

    data : array_like
        Input signal.
    wavelet : Wavelet object or name
        Wavelet to use
    mode : str, optional
        Signal extension mode, see `Modes`.  Default is 'symmetric'.
    level : int, optional
        Decomposition level.  Default is 1.

    Returns
    -------
    coeffs : ndarray
        1-D array of coefficients.

    See Also
    --------
    upcoef

    """
    if np.iscomplexobj(data):
        return (downcoef(part, data.real, wavelet, mode, level) +
                1j*downcoef(part, data.imag, wavelet, mode, level))
    # accept array_like input; make a copy to ensure a contiguous array
    dt = _check_dtype(data)
    data = np.array(data, dtype=dt)
    return _downcoef(part, data, wavelet, mode, level)


def _downcoef(part, np.ndarray[data_t, ndim=1, mode="c"] data,
              object wavelet, object mode='symmetric', int level=1):
    cdef np.ndarray[data_t, ndim=1, mode="c"] coeffs
    cdef int i, do_dec_a
    cdef index_t dec_len
    cdef Wavelet w
    cdef common.MODE mode_

    w = c_wavelet_from_object(wavelet)
    mode_ = _try_mode(mode)

    if part not in ('a', 'd'):
        raise ValueError("Argument 1 must be 'a' or 'd', not '%s'." % part)
    do_dec_a = (part == 'a')

    if level < 1:
        raise ValueError("Value of level must be greater than 0.")

    for i in range(level):
        output_len = common.dwt_buffer_length(data.size, w.dec_len, mode_)
        if output_len < 1:
            raise RuntimeError("Invalid output length.")
        coeffs = np.zeros(output_len, dtype=data.dtype)

        # To mirror multi-level wavelet decomposition behaviour, when detail
        # coefficients are requested, the dec_d variant is only called at the
        # final level.  All prior levels use dec_a.  In other words, the detail
        # coefficients at level n are those produced via the operation of the
        # detail filter on the approximation coefficients of level n-1.
        if do_dec_a or (i < level - 1):
            if data_t is np.float64_t:
                if c_wt.double_dec_a(&data[0], data.size, w.w,
                                     &coeffs[0], coeffs.size, mode_) < 0:
                    raise RuntimeError("C dec_a failed.")
            elif data_t is np.float32_t:
                if c_wt.float_dec_a(&data[0], data.size, w.w,
                                    &coeffs[0], coeffs.size, mode_) < 0:
                    raise RuntimeError("C dec_a failed.")
            else:
                raise RuntimeError("Invalid data type.")
        else:
            if data_t is np.float64_t:
                if c_wt.double_dec_d(&data[0], data.size, w.w,
                                     &coeffs[0], coeffs.size, mode_) < 0:
                    raise RuntimeError("C dec_d failed.")
            elif data_t is np.float32_t:
                if c_wt.float_dec_d(&data[0], data.size, w.w,
                                    &coeffs[0], coeffs.size, mode_) < 0:
                    raise RuntimeError("C dec_d failed.")
            else:
                raise RuntimeError("Invalid data type.")
        data = coeffs

    return coeffs


###############################################################################
# swt

def swt_max_level(input_len):
    """
    swt_max_level(input_len)

    Calculates the maximum level of Stationary Wavelet Transform for data of
    given length.

    Parameters
    ----------
    input_len : int
        Input data length.

    Returns
    -------
    max_level : int
        Maximum level of Stationary Wavelet Transform for data of given length.

    """
    return common.swt_max_level(input_len)


def swt(data, object wavelet, object level=None, int start_level=0):
    """
    swt(data, wavelet, level=None, start_level=0)

    Performs multilevel Stationary Wavelet Transform.

    Parameters
    ----------
    data :
        Input signal
    wavelet :
        Wavelet to use (Wavelet object or name)
    level : int, optional
        Transform level.
    start_level : int, optional
        The level at which the decomposition will begin (it allows one to
        skip a given number of transform steps and compute
        coefficients starting from start_level) (default: 0)

    Returns
    -------
    coeffs : list
        List of approximation and details coefficients pairs in order
        similar to wavedec function::

            [(cAn, cDn), ..., (cA2, cD2), (cA1, cD1)]

        where ``n`` equals input parameter `level`.

        If *m* = *start_level* is given, then the beginning *m* steps are skipped::

            [(cAm+n, cDm+n), ..., (cAm+1, cDm+1), (cAm, cDm)]

    """
    if np.iscomplexobj(data):
        data = np.asarray(data)
        coeffs_real = swt(data.real, wavelet, level, start_level)
        coeffs_imag = swt(data.imag, wavelet, level, start_level)
        coeffs_cplx = []
        for (cA_r, cD_r), (cA_i, cD_i) in zip(coeffs_real, coeffs_imag):
            coeffs_cplx.append((cA_r + 1j*cA_i, cD_r + 1j*cD_i))
        return coeffs_cplx

    # accept array_like input; make a copy to ensure a contiguous array
    dt = _check_dtype(data)
    data = np.array(data, dtype=dt)
    return _swt(data, wavelet, level, start_level)


def _swt(np.ndarray[data_t, ndim=1, mode="c"] data, object wavelet,
         object level=None, int start_level=0):
    """See `swt` for details."""
    cdef np.ndarray[data_t, ndim=1, mode="c"] cA, cD
    cdef Wavelet w
    cdef int i, end_level, level_

    if data.size % 2:
        raise ValueError("Length of data must be even.")

    w = c_wavelet_from_object(wavelet)

    if level is None:
        level_ = common.swt_max_level(data.size)
    else:
        level_ = level

    end_level = start_level + level_

    if level_ < 1:
        raise ValueError("Level value must be greater than zero.")
    if start_level < 0:
        raise ValueError("start_level must be greater than zero.")
    if start_level >= common.swt_max_level(data.size):
        raise ValueError("start_level must be less than %d." %
                         common.swt_max_level(data.size))

    if end_level > common.swt_max_level(data.size):
        msg = ("Level value too high (max level for current data size and "
               "start_level is %d)." % (common.swt_max_level(data.size) -
                                        start_level))
        raise ValueError(msg)

    # output length
    output_len = common.swt_buffer_length(data.size)
    if output_len < 1:
        raise RuntimeError("Invalid output length.")

    ret = []
    for i in range(start_level+1, end_level+1):
        # alloc memory, decompose D
        cD = np.zeros(output_len, dtype=data.dtype)

        if data_t is np.float64_t:
            if c_wt.double_swt_d(&data[0], data.size, w.w,
                                 &cD[0], cD.size, i) < 0:
                raise RuntimeError("C swt failed.")
        elif data_t is np.float32_t:
            if c_wt.float_swt_d(&data[0], data.size, w.w,
                                &cD[0], cD.size, i) < 0:
                raise RuntimeError("C swt failed.")
        else:
            raise RuntimeError("Invalid data type.")

        # alloc memory, decompose A
        cA = np.zeros(output_len, dtype=data.dtype)

        if data_t is np.float64_t:
            if c_wt.double_swt_a(&data[0], data.size, w.w,
                                 &cA[0], cA.size, i) < 0:
                raise RuntimeError("C swt failed.")
        elif data_t is np.float32_t:
            if c_wt.float_swt_a(&data[0], data.size, w.w,
                                &cA[0], cA.size, i) < 0:
                raise RuntimeError("C swt failed.")
        else:
            raise RuntimeError("Invalid data type.")

        data = cA
        ret.append((cA, cD))

    ret.reverse()
    return ret


def keep(arr, keep_length):
    length = len(arr)
    if keep_length < length:
        left_bound = (length - keep_length) / 2
        return arr[left_bound:left_bound + keep_length]
    return arr


# Some utility functions

cdef object float64_array_to_list(double* data, index_t n):
    cdef index_t i
    cdef object app
    cdef object ret
    ret = []
    app = ret.append
    for i in range(n):
        app(data[i])
    return ret


cdef void copy_object_to_float64_array(source, double* dest) except *:
    cdef index_t i
    cdef double x
    i = 0
    for x in source:
        dest[i] = x
        i = i + 1


cdef void copy_object_to_float32_array(source, float* dest) except *:
    cdef index_t i
    cdef float x
    i = 0
    for x in source:
        dest[i] = x
        i = i + 1
